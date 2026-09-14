#!/usr/bin/env python3
"""Independent integer-oracle arithmetic regression for the active project format.

Reads and validates the fresh YAML-derived RTL header, then compiles an isolated
copy of this project's RTL. It never changes the project's header or sources.
The oracle uses Python integers and does not call fixed_math/nominal_models.
Run this script in each configured project to cover Q8.16, Q8.14, and Q8.12.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import shutil
import subprocess
import tempfile

import nominal_config

ROOT = Path(__file__).resolve().parents[1]
SEED = 220916

TESTBENCH = r"""`timescale 1ns/1ps
`include "rtl/common/fx_q8_16_defs.vh"
module tb;
localparam W=`FX_Q8_16_WIDTH, P=`FX_Q8_16_PRODUCT_WIDTH, M=`FX_Q8_16_MAC_WIDTH;
reg signed [W-1:0] a,b,c,d,e,f;
reg signed [P-1:0] raw_p;
reg signed [M-1:0] raw_m;
wire signed [W-1:0] add_y,sub_y,mul_y,mac_y;
wire add_o,sub_o,mul_o,mac_o;
reg signed [63:0] ea,eao,es,eso,ep,epo,em,emo,eavg,efp,efpo,efm,efmo,ereduce;
integer fd,scan,n;
`include "rtl/common/fx_q8_16_functions.vh"
q8_16_add_sat u_add(a,b,add_y,add_o);
q8_16_sub_sat u_sub(a,b,sub_y,sub_o);
q8_16_mul_sat u_mul(a,b,mul_y,mul_o);
q8_16_mac3_sat u_mac(a,b,c,d,e,f,mac_y,mac_o);
bkf_core #(.NUM_BRANCHES(8)) core();
initial begin
fd=$fopen("cases.txt","r"); n=0;
while (!$feof(fd)) begin
scan=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",a,b,c,d,e,f,raw_p,raw_m,ea,eao,es,eso,ep,epo,em,emo,eavg,efp,efpo,efm,efmo,ereduce);
if(scan!=22) $fatal(1,"bad case row %d",n);
#1;
if ($signed(add_y)!==ea || add_o!==eao[0] || add_sat24(a,b)!==add_y || add_overflow24(a,b)!==add_o) $fatal(1,"add case=%d a=%d b=%d actual=%d expected=%d",n,a,b,add_y,ea);
if ($signed(sub_y)!==es || sub_o!==eso[0] || sub_sat24(a,b)!==sub_y || sub_overflow24(a,b)!==sub_o) $fatal(1,"sub case=%d a=%d b=%d y=%d expected=%d ov=%b expectedov=%b func=%d funcov=%b",n,a,b,sub_y,es,sub_o,eso[0],sub_sat24(a,b),sub_overflow24(a,b));
if ($signed(mul_y)!==ep || mul_o!==epo[0]) $fatal(1,"mul case=%d a=%d b=%d actual=%d expected=%d",n,a,b,mul_y,ep);
if ($signed(mac_y)!==em || mac_o!==emo[0]) $fatal(1,"mac case=%d",n);
if ($signed(average24(a,b))!==eavg) $fatal(1,"average case=%d",n);
if ($signed(round_sat48(raw_p))!==efp || overflow48(raw_p)!==efpo[0]) $fatal(1,"raw product round case=%d",n);
if ($signed(round_sat50(raw_m))!==efm || overflow50(raw_m)!==efmo[0]) $fatal(1,"raw MAC round case=%d",n);
if ($signed(core.reduce_self_cov_l8(a))!==ereduce) $fatal(1,"rBKF reduction case=%d a=%d actual=%d expected=%d",n,a,core.reduce_self_cov_l8(a),ereduce);
n=n+1;
end
$display("PASS arithmetic_reference F=%d W=%d cases=%d",`FX_Q8_16_FRAC,W,n);
$finish;
end
endmodule
"""


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cases_for_format(width: int, frac: int) -> list[list[int]]:
    """Derive expected codes independently from exact integer arithmetic."""
    scale = 1 << frac
    low, high = -(1 << (width - 1)), (1 << (width - 1)) - 1
    rng = random.Random(SEED)

    def nearest_away(value: int, shift: int = frac) -> int:
        magnitude = (abs(value) + (1 << (shift - 1))) // (1 << shift)
        return -magnitude if value < 0 else magnitude

    def saturate(value: int) -> list[int]:
        return [min(high, max(low, value)), int(value < low or value > high)]

    edges = [low, low + 1, -scale, -scale // 2, -2, -1, 0, 1, 2,
             scale // 2, scale, high - 1, high]
    operands = [[a, b, low, high, high, low] for a in edges for b in edges]
    operands += [[sign, scale // 2 + delta, 1, scale // 2, 0, 0]
                 for sign in (-1, 1) for delta in (-1, 0, 1)]
    operands += [[rng.randint(low, high) for _ in range(6)] for _ in range(4000)]
    operands += [[rng.randint(-scale, scale) for _ in range(6)] for _ in range(1000)]
    records = []
    for index, values in enumerate(operands):
        a, b, c, d, e, f = values

        def raw_accumulator(bits: int) -> int:
            corners = [-(1 << (bits - 1)), -(1 << (bits - 1)) + 1,
                       -scale // 2 - 1, -scale // 2, -scale // 2 + 1,
                       scale // 2 - 1, scale // 2, scale // 2 + 1,
                       (1 << (bits - 1)) - 1,
                       (high << frac) + scale // 2, (low << frac) - scale // 2]
            return corners[index] if index < len(corners) else rng.randint(
                -(1 << (bits - 1)), (1 << (bits - 1)) - 1)

        product_input = raw_accumulator(2 * width)
        mac_input = raw_accumulator(2 * width + 2)
        expected = (saturate(a + b) + saturate(a - b)
                    + saturate(nearest_away(a * b))
                    + saturate(nearest_away(a * b + c * d + e * f))
                    + [nearest_away(a + b, 1)]
                    + saturate(nearest_away(product_input))
                    + saturate(nearest_away(mac_input))
                    + [nearest_away(scale + 7 * a, 3)])
        records.append(values + [product_input, mac_input] + expected)
    return records


def execute(command: list[str], cwd: Path, logfile: Path) -> subprocess.CompletedProcess:
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired as exc:
        def string(value):
            return value.decode(errors="replace") if isinstance(value, bytes) else value or ""
        logfile.write_text(string(exc.stdout) + string(exc.stderr) + "\nTIMEOUT after 30 seconds\n")
        raise RuntimeError(f"timeout: {command[0]}") from exc
    logfile.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"{command[0]} exited {result.returncode}; see {logfile}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path,
                        default=ROOT / "results" / "bitwidth" / "audit",
                        help="Audit artifact directory (defaults to this project's results)")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    width, frac = nominal_config.WIDTH, nominal_config.FRAC
    label = f"arithmetic_q8_{frac}"
    artifacts = output / label
    artifacts.mkdir(parents=True, exist_ok=True)
    (artifacts / "simulation.log").write_text("")
    summary = {"status": "FAIL", "q_format": f"Q8.{frac}", "signed_width": width,
               "fractional_bits": frac, "random_seed": SEED, "expected_cases": 5175,
               "completed_cases": 0, "first_failed_case": None,
               "oracle": "Independent exact Python integer arithmetic; no fixed-point model calls",
               "checks": ["add/sub result and overflow", "multiply result and overflow",
                          "three-term full-product MAC result and overflow",
                          "common saturation/rounding helpers including minimum full accumulators",
                          "ties-away average", "rBKF (1+7*rho)/8 reduction"],
               "source_project": str(ROOT)}
    try:
        nominal_config.validate_generated_header()
        header = ROOT / "rtl" / "common" / "fx_q8_16_defs.vh"
        header_text = header.read_text(encoding="ascii")
        for name, expected in {"WIDTH": width, "FRAC": frac,
                               "PRODUCT_WIDTH": 2 * width, "MAC_WIDTH": 2 * width + 2}.items():
            match = re.search(rf"^`define FX_Q8_16_{name} (\d+)$", header_text, re.MULTILINE)
            if match is None or int(match.group(1)) != expected:
                raise ValueError(f"Generated RTL macro {name} does not match YAML")
        summary["config_sha256"] = digest(ROOT / "config" / "nominal.yaml")
        summary["rtl_header_sha256"] = digest(header)
        summary["rtl_sha256"] = {str(path.relative_to(ROOT)): digest(path)
                                 for path in sorted((ROOT / "rtl").rglob("*"))
                                 if path.is_file() and path.suffix in (".v", ".vh", ".hex")}
        records = cases_for_format(width, frac)
        if len(records) != summary["expected_cases"]:
            raise AssertionError("Arithmetic vector count changed without updating the contract")
        case_path = artifacts / "cases.txt"
        case_path.write_text("".join(" ".join(map(str, row)) + "\n" for row in records))
        (artifacts / "testbench.v").write_text(TESTBENCH)
        (artifacts / "fx_q8_16_defs.vh").write_text(header_text, encoding="ascii")
        summary["cases_sha256"] = digest(case_path)
        summary["testbench_sha256"] = digest(artifacts / "testbench.v")
        with tempfile.TemporaryDirectory(prefix="bkf_arithmetic_reference_") as directory:
            work = Path(directory)
            shutil.copytree(ROOT / "rtl", work / "rtl")
            shutil.copy2(case_path, work / "cases.txt")
            shutil.copy2(artifacts / "testbench.v", work / "tb.v")
            rtl_files = [str(path.relative_to(work)) for path in sorted((work / "rtl").rglob("*.v"))]
            command = ["iverilog", "-g2001", "-I.", "-s", "tb", "-o", "tb.vvp", "tb.v", *rtl_files]
            summary["compile_command"] = command
            execute(command, work, artifacts / "compile.log")
            result = execute(["vvp", "tb.vvp"], work, artifacts / "simulation.log")
            match = re.search(r"PASS arithmetic_reference F=\s*(\d+) W=\s*(\d+) cases=\s*(\d+)", result.stdout)
            if match is None or tuple(map(int, match.groups())) != (frac, width, len(records)):
                raise RuntimeError("Missing complete PASS marker or wrong format/case count")
            if re.search(r"(?:ERROR|FATAL|WARNING):", result.stdout + result.stderr):
                raise RuntimeError("Simulator emitted a diagnostic; inspect simulation.log")
            summary["completed_cases"] = len(records)
            summary["status"] = "PASS"
    except Exception as exc:
        summary["error"] = str(exc)
        log = artifacts / "simulation.log"
        if log.exists():
            match = re.search(r"case=\s*(\d+)", log.read_text())
            if match:
                summary["first_failed_case"] = int(match.group(1))
                summary["completed_cases"] = int(match.group(1))
    (output / f"{label}.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{summary['status']}: independent arithmetic Q8.{frac}, "
          f"{summary['completed_cases']}/{summary['expected_cases']} cases")
    if summary["status"] != "PASS":
        print(summary.get("error", "unknown failure"))
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
