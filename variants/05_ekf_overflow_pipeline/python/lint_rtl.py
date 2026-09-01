#!/usr/bin/env python3
"""Dependency-free RTL policy lint plus Icarus top-level elaboration."""

from __future__ import annotations

import re
import subprocess

from common import ROOT


def strip_comments_strings(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return re.sub(r"^\s*`timescale.*$", "", text, flags=re.M)


def main() -> None:
    errors: list[str] = []
    for path in sorted((ROOT / "rtl").rglob("*.v")):
        source = path.read_text(encoding="utf-8")
        clean = strip_comments_strings(source)
        for forbidden in ("$asin", "$sqrt", "$pow"):
            if forbidden in clean:
                errors.append(f"{path.relative_to(ROOT)}: forbidden {forbidden}")
        if re.search(r"\breal\b", clean):
            errors.append(f"{path.relative_to(ROOT)}: forbidden real")
        if "/" in clean:
            errors.append(f"{path.relative_to(ROOT)}: synthesizable division operator remains")
        if "`default_nettype none" not in source:
            errors.append(f"{path.relative_to(ROOT)}: missing default_nettype none")
    if errors:
        raise SystemExit("\n".join(errors))

    common = [
        "rtl/common/fx_divider_q8_16.v",
        "rtl/common/fx_determinant_finalize_pipeline.v",
        "rtl/common/fx_mul_mac_pipeline.v",
        "rtl/nonlinear/q8_16_rsqrt_lut.v",
        "rtl/nonlinear/arcsine_cov_lut_q8_16.v", "rtl/bkf/bkf_core.v",
    ]
    tops = {
        "ekf_core": common + ["rtl/ekf/ekf_core.v"],
        "bkf_l1_core": common + ["rtl/bkf/bkf_l1_core.v"],
        "rbkf_core": common + ["rtl/rbkf/rbkf_core.v"],
    }
    out_dir = ROOT / "results" / "rtl"
    out_dir.mkdir(parents=True, exist_ok=True)
    for top, sources in tops.items():
        subprocess.run(
            ["iverilog", "-g2001", "-gstrict-expr-width", "-Wall",
             "-Wno-sensitivity-entire-array", "-Wimplicit", "-I.",
             "-s", top, "-o", str(out_dir / f"lint_{top}.vvp"), *sources],
            cwd=ROOT, check=True,
        )
    print(f"PASS: RTL policy lint and {len(tops)} top-level elaborations")


if __name__ == "__main__":
    main()
