#!/usr/bin/env python3
"""Generate the three required nominal comparison figures."""

from __future__ import annotations

import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from common import RESULTS_DIR
from fixed_math import SCALE


ALGORITHMS = ("ekf", "bkf_l1", "rbkf_l8")
LABELS = {"ekf": "EKF (ideal)", "bkf_l1": "BKF L=1", "rbkf_l8": "rBKF L=8"}
COLORS = {"ekf": "#0072B2", "bkf_l1": "#D55E00", "rbkf_l8": "#009E73"}


def load_rtl(name: str, expected_steps: int) -> np.ndarray:
    path = RESULTS_DIR / f"rtl_{name}_outputs.csv"
    if not path.is_file():
        raise FileNotFoundError(
            f"Missing RTL output for {name}: {path}\n"
            "Run `make test` before `make plots` to generate the RTL CSV files."
        )
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != expected_steps:
        raise ValueError(
            f"RTL output row count mismatch for {name}: expected {expected_steps}, "
            f"got {len(rows)} ({path}).\n"
            "Run `make test` before `make plots` to regenerate the RTL CSV files."
        )
    return np.asarray([[int(row[f"state_{i}_int"]) for i in range(3)] for row in rows]) / SCALE


def main() -> None:
    output = RESULTS_DIR / "plots"
    output.mkdir(parents=True, exist_ok=True)
    target = np.load(RESULTS_DIR / "reference" / "stimulus.npz")["target"]
    fixed = {name: np.load(RESULTS_DIR / "reference" / f"fixed_{name}.npz")["state_post"] / SCALE for name in ALGORITHMS}
    floating = {name: np.load(RESULTS_DIR / "reference" / f"float_{name}.npz")["state_post"] for name in ALGORITHMS}
    rtl = {name: load_rtl(name, len(target)) for name in ALGORITHMS}
    time = np.arange(len(target))

    fig, axes = plt.subplots(3, 1, figsize=(11, 8), sharex=True)
    for state, axis in enumerate(axes):
        axis.plot(time, target[:, state], color="black", linewidth=1.4, label="Ground truth")
        for name in ALGORITHMS:
            axis.plot(time, fixed[name][:, state], color=COLORS[name], linewidth=0.9, label=LABELS[name])
        axis.set_ylabel(f"x{state + 1}")
        axis.grid(alpha=0.25)
    axes[0].legend(ncol=4, fontsize=8)
    axes[-1].set_xlabel("Time step")
    fig.tight_layout()
    fig.savefig(output / "state_trajectory.png", dpi=180)
    plt.close(fig)

    fig, axis = plt.subplots(figsize=(11, 4.5))
    for name in ALGORITHMS:
        error_norm = np.linalg.norm(fixed[name] - target, axis=1)
        axis.plot(time, error_norm, color=COLORS[name], linewidth=1.0, label=LABELS[name])
    axis.set(xlabel="Time step", ylabel="Euclidean error norm", title="Nominal estimation error")
    axis.grid(alpha=0.25)
    axis.legend()
    fig.tight_layout()
    fig.savefig(output / "error_norm.png", dpi=180)
    plt.close(fig)

    fig, axes = plt.subplots(3, 3, figsize=(13, 8), sharex=True)
    for row, name in enumerate(ALGORITHMS):
        for state in range(3):
            axis = axes[row, state]
            axis.plot(time, floating[name][:, state], color="#777777", linewidth=1.2, label="float")
            axis.plot(time, fixed[name][:, state], color=COLORS[name], linewidth=0.9, label="fixed")
            axis.plot(time, rtl[name][:, state], color="#CC79A7", linestyle="--", linewidth=0.7, label="RTL")
            if state == 0:
                axis.set_ylabel(LABELS[name])
            if row == 0:
                axis.set_title(f"x{state + 1}")
            axis.grid(alpha=0.2)
    axes[0, 0].legend(fontsize=8)
    for axis in axes[-1]:
        axis.set_xlabel("Time step")
    fig.tight_layout()
    fig.savefig(output / "float_fixed_rtl_comparison.png", dpi=180)
    plt.close(fig)
    print("PASS: generated nominal trajectory, error-norm, and float/fixed/RTL plots")


if __name__ == "__main__":
    main()
