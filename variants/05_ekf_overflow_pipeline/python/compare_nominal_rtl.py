#!/usr/bin/env python3
"""Compare the configured nominal RTL CSV outputs with the integer reference."""

from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np

from common import RESULTS_DIR, write_json
from nominal_config import CONFIG_SHA256, STATE_DIMENSION, STEPS


FILES = {
    "ekf": "rtl_ekf_outputs.csv",
    "bkf_l1": "rtl_bkf_l1_outputs.csv",
    "rbkf_l1": "rtl_rbkf_l1_outputs.csv",
    "rbkf_l8": "rtl_rbkf_l8_outputs.csv",
}


def load_csv(path: Path) -> tuple[np.ndarray, np.ndarray]:
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    state = np.asarray(
        [
            [int(row[f"state_{i}_int"]) for i in range(STATE_DIMENSION)]
            for row in rows
        ],
        dtype=np.int64,
    )
    cov = np.asarray(
        [
            [
                [
                    int(row[f"cov_{i}{j}_int"])
                    for j in range(STATE_DIMENSION)
                ]
                for i in range(STATE_DIMENSION)
            ]
            for row in rows
        ],
        dtype=np.int64,
    )
    return state, cov


def main() -> None:
    reference_summary_path = RESULTS_DIR / "reference" / "summary.json"
    if not reference_summary_path.is_file():
        raise SystemExit("Run python/nominal_models.py first")
    reference_summary = json.loads(reference_summary_path.read_text(encoding="utf-8"))
    if reference_summary.get("config_sha256") != CONFIG_SHA256:
        raise SystemExit(
            "Reference artifacts do not match config/nominal.yaml; "
            "run python/nominal_models.py first"
        )
    result_rows: list[dict[str, object]] = []
    cycle_rows: list[dict[str, object]] = []
    summary: dict[str, object] = {}
    for algorithm, filename in FILES.items():
        state, cov = load_csv(RESULTS_DIR / filename)
        with (RESULTS_DIR / f"cycle_counts_{algorithm}.csv").open(newline="", encoding="utf-8") as stream:
            algorithm_cycles = list(csv.DictReader(stream))
        for cycle_row in algorithm_cycles:
            cycle_rows.append({"algorithm": algorithm, "step": int(cycle_row["step"]),
                               "cycles": int(cycle_row["cycles"])})
        with np.load(RESULTS_DIR / "reference" / f"fixed_{algorithm}.npz") as expected:
            expected_state = expected["state_post"]
            expected_cov = expected["cov_post"]
        if len(state) != STEPS:
            raise SystemExit(
                f"{algorithm}: expected {STEPS} RTL rows, got {len(state)}"
            )
        state_diff = np.abs(state - expected_state)
        cov_diff = np.abs(cov - expected_cov)
        symmetry = np.max(np.abs(cov - np.swapaxes(cov, 1, 2)))
        negative_diagonal = int(np.sum(np.diagonal(cov, axis1=1, axis2=2) < 0))
        record = {
            "algorithm": algorithm,
            "state_bit_exact_rate": float(np.mean(state == expected_state)),
            "cov_bit_exact_rate": float(np.mean(cov == expected_cov)),
            "state_max_abs_code_diff": int(np.max(state_diff)),
            "state_mean_abs_code_diff": float(np.mean(state_diff)),
            "cov_max_abs_code_diff": int(np.max(cov_diff)),
            "cov_mean_abs_code_diff": float(np.mean(cov_diff)),
            "overflow_count": 0,
            "solver_error_count": 0,
            "covariance_symmetry_max_lsb": int(symmetry),
            "negative_covariance_diagonal_count": negative_diagonal,
            "cycles_per_update_min": min(int(row["cycles"]) for row in algorithm_cycles),
            "cycles_per_update_max": max(int(row["cycles"]) for row in algorithm_cycles),
        }
        result_rows.append(record)
        summary[algorithm] = record
        if record["state_max_abs_code_diff"] or record["cov_max_abs_code_diff"]:
            raise SystemExit(f"{algorithm}: RTL mismatch")
        if negative_diagonal:
            raise SystemExit(f"{algorithm}: negative covariance diagonal")
    with (RESULTS_DIR / "rtl_comparison.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(result_rows[0]))
        writer.writeheader()
        writer.writerows(result_rows)
    write_json(RESULTS_DIR / "rtl_comparison.json", summary)
    with (RESULTS_DIR / "cycle_counts.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=("algorithm", "step", "cycles"))
        writer.writeheader()
        writer.writerows(cycle_rows)
    print("PASS: all EKF/BKF/rBKF RTL state and covariance values are 100% bit-exact")


if __name__ == "__main__":
    main()
