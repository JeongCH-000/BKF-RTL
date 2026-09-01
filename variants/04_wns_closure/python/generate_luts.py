#!/usr/bin/env python3
"""Generate deterministic readmemh images for the nonlinear RTL units."""

from __future__ import annotations

from pathlib import Path

from common import ROOT
from fixed_math import ASIN_DEPTH, RSQRT_DEPTH, WIDTH, make_asin_lut, make_rsqrt_lut


def write_hex(path: Path, values) -> None:
    mask = (1 << WIDTH) - 1
    digits = (WIDTH + 3) // 4
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii") as stream:
        for value in values:
            stream.write(f"{int(value) & mask:0{digits}x}\n")


def main() -> None:
    rsqrt = make_rsqrt_lut()
    arcsine_cov = make_asin_lut()
    write_hex(ROOT / "rtl" / "nonlinear" / "rsqrt_q16.hex", rsqrt)
    write_hex(ROOT / "rtl" / "nonlinear" / "arcsine_cov_q16.hex", arcsine_cov)
    print(f"Generated rsqrt LUT: {RSQRT_DEPTH} x {WIDTH}")
    print(f"Generated (2/pi)*asin covariance LUT: {ASIN_DEPTH} x {WIDTH}")


if __name__ == "__main__":
    main()
