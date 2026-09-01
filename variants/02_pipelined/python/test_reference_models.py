#!/usr/bin/env python3
"""Executable algorithm and fixed-point invariants independent of RTL."""

from __future__ import annotations

import numpy as np

from common import RESULTS_DIR, write_json
from fixed_math import (
    ONE, R_DIAG, SCALE, ArithmeticStats, asin_lookup, fx_add, fx_div, fx_mul, fx_sub,
    make_asin_lut, make_rsqrt_lut, quantize_scalar, round_shift_away, rsqrt_lookup,
)
from nominal_models import (
    RBKF_BRANCHES, divide_integer_away,
    full_reduced_covariance_float,
    reduced_covariance_float,
    run_all,
)


def main() -> None:
    checks = 0
    assert quantize_scalar(1.0) == ONE
    assert quantize_scalar(-1.0) == -ONE
    assert round_shift_away(32768, 16) == 1
    assert round_shift_away(-32768, 16) == -1
    assert fx_add(8_388_607, 1) == 8_388_607
    assert fx_sub(-8_388_608, 1) == -8_388_608
    assert fx_mul(ONE, -ONE) == -ONE
    assert fx_div(ONE, 2 * ONE) == ONE // 2
    checks += 8

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
        "rsqrt_max_abs_error_at_bin_centers": rsqrt_error,
        "arcsine_cov_max_abs_error_at_grid_points": arcsine_error,
        "reduced_covariance_formula_max_abs_error": maximum_formula_error,
    })
    print(f"PASS: reference invariants ({checks} checks, reduced formula max error {maximum_formula_error:.3g}, "
          f"LUT errors rsqrt={rsqrt_error:.3g}, arcsine_cov={arcsine_error:.3g})")


if __name__ == "__main__":
    main()
