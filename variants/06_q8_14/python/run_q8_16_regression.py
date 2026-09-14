#!/usr/bin/env python3
"""Reproduce generalized Q8.16 versus latest original in independent temporary copies.

Requires this project's configured Python environment, Icarus Verilog, and the
Q8.16 project selected with --source (default: ../05_ekf_overflow_pipeline). Original files and
current experiment sources are read-only. Generated results, vectors, LUTs,
virtual environments, caches, builds, waveforms, and Vivado runs are excluded
from both input copies. Optional raw BKF_python input data are copied as ordinary files.
No Vivado command or waveform target is run.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

import yaml

ROOT = Path(__file__).resolve().parents[1]
ALGORITHMS = ("ekf", "bkf", "rbkf_l1", "rbkf_l8")
EXCLUDED_NAMES = {".git", ".venv", "__pycache__", ".pytest_cache", ".mypy_cache",
                  ".ruff_cache", ".Xil", ".DS_Store", "sim_build", "build", "dist",
                  "node_modules", "work", "vivado_work", "vivado_runs"}
EXCLUDED_SUFFIXES = {".pyc", ".pyo", ".vvp", ".vcd", ".fst", ".saif", ".jou", ".dcp",
                     ".wdb", ".pb", ".o", ".so"}
EXCLUSION_POLICY = {
    "directory_names": sorted(EXCLUDED_NAMES),
    "directory_suffixes": [".cache", ".runs", ".sim", ".hw", ".ip_user_files"],
    "file_suffixes": sorted(EXCLUDED_SUFFIXES),
    "generated_trees": ["results/", "vectors/", "tb/vectors/"],
    "generated_luts": "rtl/nonlinear/*.hex",
    "preserved_raw_inputs": "BKF_python/** ordinary file copies; no links to originals",
}


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def excluded(relative: Path, *, generated: bool) -> bool:
    if any(part in EXCLUDED_NAMES or part.endswith((".cache", ".runs", ".sim", ".hw", ".ip_user_files"))
           for part in relative.parts):
        return True
    if relative.suffix in EXCLUDED_SUFFIXES or relative.name.startswith("vivado."):
        return True
    if generated:
        if relative.parts[0] in ("results", "vectors") or relative.parts[:2] == ("tb", "vectors"):
            return True
        if relative.parts[:2] == ("rtl", "nonlinear") and relative.suffix == ".hex":
            return True
    return False


def input_files(project: Path) -> list[Path]:
    files = []
    for directory, names, filenames in os.walk(project):
        current = Path(directory)
        names[:] = sorted(name for name in names if not excluded((current / name).relative_to(project), generated=True))
        for name in names:
            if (current / name).is_symlink():
                raise ValueError(f"Directory symlink is not an independent project input: {current / name}")
        for name in sorted(filenames):
            path = current / name
            if not excluded(path.relative_to(project), generated=True):
                if not path.is_file():
                    raise ValueError(f"Non-regular project input: {path}")
                files.append(path)
    return sorted(files)


def manifest(project: Path) -> dict[str, str]:
    return {str(path.relative_to(project)): sha256(path) for path in input_files(project)}


def independent_copy(project: Path, destination: Path) -> None:
    destination.mkdir(parents=True)
    for path in input_files(project):
        target = destination / path.relative_to(project)
        target.parent.mkdir(parents=True, exist_ok=True)
        # copy2 follows file symlinks into regular files; never create hardlinks.
        shutil.copy2(path, target, follow_symlinks=True)
        if target.is_symlink() or os.path.samestat(path.stat(), target.stat()):
            raise AssertionError(f"Input copy is not independent: {target}")


def archive_evidence(project: Path, destination: Path) -> None:
    """Keep checker-readable roots and all logs/data, without duplicate raw .pt or builds."""
    destination.mkdir(parents=True, exist_ok=True)
    for directory, names, filenames in os.walk(project):
        current = Path(directory)
        names[:] = sorted(name for name in names
                          if not excluded((current / name).relative_to(project), generated=False)
                          and (current / name).relative_to(project).parts[0] != "BKF_python"
                          and (current / name).relative_to(project).parts[:2]
                          not in (("results", "waveform"), ("results", "plots"),
                                  ("results", "synthesis"), ("results", "vivado")))
        for name in sorted(filenames):
            path = current / name
            relative = path.relative_to(project)
            if not excluded(relative, generated=False):
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)


def unique_directory(requested: Path) -> Path:
    if not requested.exists():
        requested.mkdir(parents=True)
        return requested
    version = 2
    while True:
        candidate = requested.with_name(f"{requested.name}_v{version}")
        if not candidate.exists():
            candidate.mkdir(parents=True)
            return candidate
        version += 1


def set_generalized_q16(project: Path) -> None:
    path = project / "config" / "nominal.yaml"
    text = path.read_text()
    before = yaml.safe_load(text)
    for key, value in (("signed_width", "24"), ("fractional_bits", "16"),
                       ("saturation", "signed_24_bit")):
        text, count = re.subn(rf"(?m)^(\s+{key}:\s*)[^\n]+$", rf"\g<1>{value}", text)
        if count != 1:
            raise ValueError(f"Expected exactly one fixed_point.{key} setting")
    after = yaml.safe_load(text)
    if {k: v for k, v in before.items() if k != "fixed_point"} != {
            k: v for k, v in after.items() if k != "fixed_point"}:
        raise AssertionError("Attempted change outside fixed_point")
    if after["fixed_point"] != {"signed_width": 24, "fractional_bits": 16,
                                "rounding": "nearest_ties_away_from_zero", "saturation": "signed_24_bit"}:
        raise AssertionError("Unexpected fixed-point contract")
    path.write_text(text)


def run_command(project: Path, name: str, command: list[str], records: list[dict],
                env: dict[str, str], timeout: int) -> bool:
    log = project / "results" / "bitwidth" / "logs" / f"{name}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    print(f"RUN {project.name}: {name}", flush=True)
    with log.open("w") as stream:
        stream.write("command: " + json.dumps(command) + "\n")
        stream.flush()
        try:
            completed = subprocess.run(command, cwd=project, stdout=stream,
                                       stderr=subprocess.STDOUT, env=env, timeout=timeout)
            code = completed.returncode
        except subprocess.TimeoutExpired:
            code = 124
            stream.write(f"\nTIMEOUT after {timeout} seconds\n")
        except OSError as error:
            code = 127
            stream.write(f"\n{error}\n")
    if code == 0 and re.search(r"(?m)^\s*(?:FAIL|FATAL|ERROR):", log.read_text(errors="replace")):
        code = 1
    record = {"test": name, "command": command, "returncode": code,
              "status": "PASS" if code == 0 else ("INCOMPLETE" if code in (124, 127) else "FAIL"),
              "seconds": round(time.monotonic() - start, 3), "log": str(log.relative_to(project))}
    records.append(record)
    write_json(project / "results" / "bitwidth" / "test_status.json", records)
    print(f"{record['status']} {project.name}: {name}", flush=True)
    return code == 0


def baseline_run(project: Path, python: str, env: dict[str, str], timeout: int) -> list[dict]:
    records: list[dict] = []
    for name, script in (("models", "nominal_models"), ("luts", "generate_luts"),
                         ("nominal_vectors", "generate_nominal_vectors"),
                         ("unit_vectors", "generate_unit_vectors"),
                         ("reference_tests", "test_reference_models"), ("lint", "lint_rtl")):
        run_command(project, name, [python, f"python/{script}.py"], records, env, timeout)
    records.append({"test": "historical_pipeline_snapshot_check", "status": "N/A",
                    "returncode": None, "required": False,
                    "reason": "Original check_wns_structure.py requires a previous-stage source snapshot under excluded results/. This historical provenance check is not a property of a fresh isolated latest-source run.",
                    "replacement": "Current generalized structural register/constraint checker, static latest-source RTL structure audit, and complete fresh Q8.16 Python/vector/RTL equivalence"})
    run_command(project, "unit_tests", ["bash", "scripts/run_unit_tests.sh"], records, env, timeout)
    for algorithm in ALGORITHMS:
        result_name = "bkf_l1" if algorithm == "bkf" else algorithm
        for steps in (1, 500):
            name = f"{algorithm}_{steps}"
            archive = project / "results" / "bitwidth" / name
            archive.mkdir(parents=True, exist_ok=True)
            outputs = (f"rtl_{result_name}_outputs.csv", f"cycle_counts_{result_name}.csv")
            for filename in outputs:
                (project / "results" / filename).unlink(missing_ok=True)
            run_command(project, name, ["bash", "scripts/run_algorithm_test.sh", algorithm, str(steps)],
                        records, env, timeout)
            for filename in outputs:
                path = project / "results" / filename
                if path.exists():
                    shutil.copy2(path, archive / filename)
    run_command(project, "compare_nominal_rtl", [python, "python/compare_nominal_rtl.py"], records, env, timeout)
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT.parent / "05_ekf_overflow_pipeline",
                        help="Q8.16 project root, read-only (default: ../05_ekf_overflow_pipeline)")
    parser.add_argument("--output", type=Path,
                        default=ROOT / "results" / "bitwidth" / "q8_16_regression_reproduction",
                        help="Durable evidence directory; existing paths receive a _v2 suffix")
    parser.add_argument("--timeout", type=int, default=600, help="Per-command timeout in seconds")
    parser.add_argument("--plan", action="store_true", help="Print orchestration steps without copying or running simulations")
    args = parser.parse_args()
    source = args.source.resolve()
    requested = args.output.resolve()
    if source == ROOT or requested.is_relative_to(source):
        parser.error("Original source must be independent, and outputs cannot be inside it")
    if not (source / "rtl" / "bkf" / "bkf_core.v").is_file():
        parser.error("--source does not contain the expected latest BKF project")
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    source_config = yaml.safe_load((source / "config" / "nominal.yaml").read_text())
    if (source_config["fixed_point"]["signed_width"], source_config["fixed_point"]["fractional_bits"]) != (24, 16):
        parser.error("Original source must be W=24/F=16")
    python = str(Path(sys.executable).absolute())
    if args.plan:
        print(json.dumps({"source": str(source), "current_project": str(ROOT), "python": python,
                          "output": str(requested), "copy_exclusions": EXCLUSION_POLICY,
                          "baseline": ["fresh Python models", "LUTs", "nominal/unit vectors", "reference tests", "lint",
                                       "original unit suite", "all four algorithms at 1 and 500 steps", "RTL comparison"],
                          "generalized": ["independent current-project copy", "only fixed_point => W24/F16",
                                          "python/run_bitwidth_experiment.py"],
                          "not_applicable": "Original historical pipeline snapshot check requires excluded old results; replaced by fresh-source structural audit and generalized structure/equivalence tests",
                          "final": ["static RTL structure audit", "archive checker inputs and logs", "check_q8_16_regression.py --original SOURCE",
                                    "compare original source/input manifest before and after"], "vivado": "NOT_RUN"}, indent=2))
        return 0
    output = unique_directory(requested)
    summary: dict = {"status": "INCOMPLETE", "source_root": str(source), "current_project": str(ROOT),
                    "output": str(output), "python_executable": python, "vivado": "NOT_RUN",
                    "copy_exclusions": EXCLUSION_POLICY, "source_unchanged": None, "failures": []}
    before = manifest(source)
    write_json(output / "source_manifest_before.json", before)
    env = dict(os.environ, PYTHON_BIN=python, PYTHONDONTWRITEBYTECODE="1", MPLBACKEND="Agg",
               PATH=str(Path(python).parent) + os.pathsep + os.environ.get("PATH", ""))
    try:
        with tempfile.TemporaryDirectory(prefix="bkf_q8_16_regression_") as directory:
            workspace = Path(directory)
            baseline = workspace / "baseline_q8_16"
            generalized = workspace / "generalized_q8_16"
            independent_copy(source, baseline)
            independent_copy(ROOT, generalized)
            # The curated Q8.16 unit suite also verifies its preceding stage.
            # Copy that RTL dependency so the baseline remains fully isolated.
            prior = source.parent / "04_wns_closure"
            if "../04_wns_closure" in (source / "scripts/run_unit_tests.sh").read_text():
                if not (prior / "rtl").is_dir():
                    raise ValueError("Q8.16 unit suite requires sibling 04_wns_closure/rtl")
                shutil.copytree(prior / "rtl", workspace / "04_wns_closure/rtl")
            if manifest(baseline) != before:
                raise AssertionError("Copied original source/raw inputs differ from the source manifest")
            set_generalized_q16(generalized)
            baseline_records = baseline_run(baseline, python, env, args.timeout)
            summary["baseline_execution_passed"] = all(item["status"] == "PASS" for item in baseline_records if item.get("required", True))
            # Outer execution records live separately: the generalized runner owns its required test_status.json.
            outer_records: list[dict] = []
            generalized_logroot = workspace / "orchestration"
            generalized_logroot.mkdir()
            generalized_ok = run_command(
                generalized_logroot, "generalized_runner",
                [python, str(generalized / "python" / "run_bitwidth_experiment.py")],
                outer_records, env, max(args.timeout, 600))
            summary["generalized_execution_passed"] = generalized_ok
            summary["structure_audit_passed"] = run_command(
                generalized_logroot, "rtl_structure_audit",
                [python, str(generalized / "python" / "audit_bitwidth_structure.py"),
                 "--source", str(baseline), "--output",
                 str(generalized / "results" / "bitwidth" / "audit" / "rtl_structure.json")],
                outer_records, env, args.timeout)
            archive_evidence(baseline, output / "baseline_q8_16")
            archive_evidence(generalized, output / "generalized_q8_16")
            archive_evidence(generalized_logroot, output / "orchestration")
        check_command = [python, str(ROOT / "python" / "check_q8_16_regression.py"),
                         "--baseline", str(output / "baseline_q8_16"),
                         "--generalized", str(output / "generalized_q8_16"),
                         "--original", str(source), "--output", str(output / "comparison.json")]
        check_records: list[dict] = []
        comparison_ok = run_command(output / "checker", "q8_16_comparison", check_command,
                                    check_records, env, args.timeout)
        summary["comparison_passed"] = comparison_ok
        if not summary["baseline_execution_passed"]:
            summary["failures"].append("Original baseline execution had failed/incomplete commands")
        if not summary["generalized_execution_passed"]:
            summary["failures"].append("Generalized execution failed/incomplete; inspect its test_status.json")
        if not summary["structure_audit_passed"]:
            summary["failures"].append("Fresh baseline/generalized static RTL structure audit failed")
        if not comparison_ok:
            summary["failures"].append("Fresh baseline/generalized comparison failed/incomplete")
    except Exception as error:
        summary["failures"].append(f"{type(error).__name__}: {error}")
    finally:
        after = manifest(source)
        write_json(output / "source_manifest_after.json", after)
        summary["source_unchanged"] = before == after
        summary["source_manifest_files"] = len(before)
        summary["source_changed_files"] = sorted(name for name in set(before) | set(after) if before.get(name) != after.get(name))
        if before != after:
            summary["failures"].append("Original source/input checksum manifest changed")
        summary["status"] = "FAIL" if summary["failures"] else "PASS"
        write_json(output / "summary.json", summary)
    print(f"{summary['status']}: isolated Q8.16 reproduction; original unchanged={summary['source_unchanged']}")
    print(f"Evidence: {output}")
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
