#!/usr/bin/env python3
"""Executable algorithm and fixed-point invariants independent of RTL."""

from __future__ import annotations

import numpy as np
import tempfile
from pathlib import Path
import yaml

from common import RESULTS_DIR, write_json
from fixed_math import (
    ONE, Q_DIAG, R_DIAG, ALPHA, SCALE, WIDTH, FRAC, FX_MIN, FX_MAX, DIAG_FLOOR, DET_FLOOR,
    ArithmeticStats, asin_lookup, fx_add, fx_div, fx_mul, fx_mac, fx_sub,
    make_asin_lut, make_rsqrt_lut, quantize_scalar, round_shift_away, rsqrt_lookup,
)
from nominal_config import CONFIG, Q_FORMAT, load_config, validate_generated_header
from nominal_models import (
    RBKF_BRANCHES, divide_integer_away,
    full_reduced_covariance_float,
    reduced_covariance_float,
    run_all,
)


def main() -> None:
    validate_generated_header()
    checks = 0
    assert quantize_scalar(1.0) == ONE
    assert quantize_scalar(-1.0) == -ONE
    assert round_shift_away(ONE // 2, FRAC) == 1
    assert round_shift_away(-ONE // 2, FRAC) == -1
    assert fx_add(FX_MAX, 1) == FX_MAX
    assert fx_sub(FX_MIN, 1) == FX_MIN
    assert fx_mul(ONE, -ONE) == -ONE
    assert fx_div(ONE, 2 * ONE) == ONE // 2
    checks += 8

    for sign in (-1, 1):
        for offset, expected in ((-1, 0), (0, 1), (1, 1)):
            assert round_shift_away(sign * (ONE // 2 + offset), FRAC) == sign * expected
            assert fx_mul(sign, ONE // 2 + offset) == sign * expected
            checks += 2
        assert quantize_scalar(sign * 0.5 / SCALE) == sign
        assert fx_div(sign, 2 * ONE) == sign
        checks += 2
    assert quantize_scalar(FX_MAX / SCALE + 1.0 / SCALE) == FX_MAX
    assert quantize_scalar(FX_MIN / SCALE - 1.0 / SCALE) == FX_MIN
    assert fx_mul(FX_MIN, ONE) == FX_MIN
    assert fx_mul(FX_MIN, -ONE) == FX_MAX
    assert fx_div(FX_MIN, FX_MIN) == ONE
    assert fx_div(FX_MIN, ONE) == FX_MIN
    assert fx_div(FX_MIN, -ONE) == FX_MAX
    assert fx_div(FX_MAX, 1) == FX_MAX
    assert fx_div(FX_MIN, 1) == FX_MIN
    checks += 9
    zero_stats = ArithmeticStats()
    for numerator in (-ONE, 0, ONE):
        assert fx_div(numerator, 0, zero_stats) == (FX_MIN if numerator < 0 else FX_MAX)
        checks += 1
    assert zero_stats.divide_by_zero_count == 3
    checks += 1
    mac_stats = ArithmeticStats()
    assert fx_mac([(FX_MIN, FX_MIN)] * 3, mac_stats) == FX_MAX
    assert mac_stats.max_abs_mac_accumulator == 3 * (1 << (2 * WIDTH - 2))
    assert mac_stats.max_abs_mac_accumulator < (1 << (2 * WIDTH + 1))
    assert Q_DIAG == quantize_scalar(0.001)
    assert R_DIAG == quantize_scalar(0.1)
    assert ALPHA == quantize_scalar(float(np.sqrt(2.0 / np.pi)))
    assert DIAG_FLOOR == DET_FLOOR == 1 << (FRAC - 10)
    checks += 7
    rsqrt_table, asin_table = make_rsqrt_lut(), make_asin_lut()
    lut_stats = ArithmeticStats()
    assert len(rsqrt_table) == 4096 and len(asin_table) == 4097
    assert rsqrt_lookup(FX_MIN, rsqrt_table, lut_stats) == int(rsqrt_table[1])
    assert rsqrt_lookup(DIAG_FLOOR, rsqrt_table) == int(rsqrt_table[1])
    assert rsqrt_lookup(4 * ONE - 1, rsqrt_table) == int(rsqrt_table[-1])
    assert rsqrt_lookup(FX_MAX, rsqrt_table) == int(rsqrt_table[-1])
    assert asin_lookup(-ONE, asin_table) == -ONE
    assert asin_lookup(ONE, asin_table) == ONE
    assert asin_lookup(FX_MIN, asin_table, lut_stats) == -ONE
    assert asin_lookup(FX_MAX, asin_table, lut_stats) == ONE
    assert asin_lookup(0, asin_table) == 0
    assert lut_stats.diagonal_floor_count == 1
    assert lut_stats.correlation_clamp_count == 2
    checks += 12

    with tempfile.TemporaryDirectory() as temporary:
        config_path = Path(temporary) / "nominal.yaml"
        for section, key, invalid in (("fixed_point", "signed_width", WIDTH + 1),
                                      ("fixed_point", "saturation", "signed_1_bit"),
                                      ("fixed_point", "rounding", "truncate"),
                                      ("noise", "process_covariance_diagonal", 0.002),
                                      ("experiment", "steps", 499)):
            altered = {name: dict(value) for name, value in CONFIG.items()}
            altered[section][key] = invalid
            config_path.write_text(yaml.safe_dump(altered), encoding="utf-8")
            try:
                load_config(config_path)
            except ValueError:
                checks += 1
            else:
                raise AssertionError(f"Invalid configuration accepted: {section}.{key}")

    stimulus, float_traces, fixed_traces = run_all()
    for model in (float_traces, {name: item.values for name, item in fixed_traces.items()}):
        left = model["bkf_l1"]
        right = model["rbkf_l1"]
        for key in left:
            if not np.array_equal(left[key], right[key]):
                raise AssertionError(f"rBKF L=1 differs from BKF at {key}")
            checks += 1

    maximum_formula_error = 0.0
    for covariance in float_traces["rbkf_l8"]["cov_predict"]:
        reduced, _, _ = reduced_covariance_float(covariance, RBKF_BRANCHES)
        general = full_reduced_covariance_float(covariance, RBKF_BRANCHES)
        maximum_formula_error = max(maximum_formula_error, float(np.max(np.abs(reduced - general))))
    if maximum_formula_error > 2.0e-15:
        raise AssertionError(f"reduced covariance formula error {maximum_formula_error}")
    checks += len(stimulus["target"])

    bits = fixed_traces["rbkf_l8"].values["branch_bits"]
    sums = fixed_traces["rbkf_l8"].values["branch_sum"]
    expected_sums = np.sum(bits.astype(np.int64) * 2 - 1, axis=1)
    if not np.array_equal(sums, expected_sums):
        raise AssertionError("feature-wise branch ordering/aggregation mismatch")
    checks += sums.size

    # Build the diagonal of full 24x24 S and apply A*S*A.T with exact
    # integer sums. It must match the RTL's directly reduced 3x3 formula.
    rsqrt_lut = make_rsqrt_lut()
    arcsine_lut = make_asin_lut()
    rbkf_fixed = fixed_traces["rbkf_l8"].values
    for step, covariance in enumerate(rbkf_fixed["cov_predict"]):
        for feature in range(3):
            stats = ArithmeticStats()
            pz_diag = fx_add(int(covariance[feature, feature]), R_DIAG, stats)
            inv_std = rsqrt_lookup(pz_diag, rsqrt_lut, stats)
            self_norm = fx_mul(fx_mul(int(covariance[feature, feature]), inv_std, stats), inv_std, stats)
            cross_branch = asin_lookup(self_norm, arcsine_lut, stats)
            full_sum = RBKF_BRANCHES * ONE + RBKF_BRANCHES * (RBKF_BRANCHES - 1) * cross_branch
            general_diagonal = divide_integer_away(full_sum, RBKF_BRANCHES * RBKF_BRANCHES)
            optimized_diagonal = int(rbkf_fixed["observation_cov"][step, feature, feature])
            if general_diagonal != optimized_diagonal:
                raise AssertionError(
                    f"fixed A*S*A.T diagonal mismatch step={step} feature={feature}: "
                    f"{general_diagonal} != {optimized_diagonal}"
                )
            checks += 1
    rsqrt = make_rsqrt_lut().astype(np.float64) / SCALE
    rsqrt_x = (np.arange(len(rsqrt), dtype=np.float64) + 0.5) / 1024.0
    rsqrt_error = float(np.max(np.abs(rsqrt - 1.0 / np.sqrt(rsqrt_x))))
    arcsine = make_asin_lut().astype(np.float64) / SCALE
    arcsine_x = -1.0 + np.arange(len(arcsine), dtype=np.float64) / 2048.0
    arcsine_error = float(np.max(np.abs(arcsine - (2.0 / np.pi) * np.arcsin(arcsine_x))))
    write_json(RESULTS_DIR / "lut_error.json", {
        "q_format": Q_FORMAT,
        "rsqrt_max_abs_error_at_bin_centers": rsqrt_error,
        "arcsine_cov_max_abs_error_at_grid_points": arcsine_error,
        "reduced_covariance_formula_max_abs_error": maximum_formula_error,
    })
    write_json(RESULTS_DIR / "bitwidth" / "reference_test_status.json", {
        "status": "PASS", "q_format": Q_FORMAT, "checks": checks,
        "scope": "arithmetic/format/algorithm identity invariants; no numerical-quality threshold asserted",
        "numerical_diagnostics": "results/bitwidth/python_numerical_diagnostics.json",
    })
    print(f"PASS: reference invariants ({checks} checks, reduced formula max error {maximum_formula_error:.3g}, "
          f"LUT errors rsqrt={rsqrt_error:.3g}, arcsine_cov={arcsine_error:.3g})")


if __name__ == "__main__":
    main()
