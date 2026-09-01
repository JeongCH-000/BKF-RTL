#!/usr/bin/env python3
"""Deterministic float and bit-accurate EKF/BKF/rBKF nominal references."""

from __future__ import annotations

import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from common import RESULTS_DIR, ROOT, ensure_result_dirs, write_json
from fixed_math import (
    ALPHA,
    ONE,
    Q_DIAG,
    R_DIAG,
    SCALE,
    ArithmeticStats,
    array_from_matrix,
    asin_lookup,
    fx_add,
    fx_mul,
    fx_sub,
    make_asin_lut,
    make_rsqrt_lut,
    matrix_inverse_3x3,
    matrix_multiply,
    matrix_symmetrize,
    matrix_transpose,
    matrix_vector_multiply,
    quantize_array,
    round_shift_away,
    rsqrt_lookup,
    saturate,
    to_matrix,
    to_vector,
)
from nominal_config import (
    BETA,
    CONFIG_SHA256,
    INITIAL_COVARIANCE_DIAGONAL,
    INITIAL_STATE as INITIAL_STATE_VALUES,
    MEASUREMENT_COVARIANCE_DIAGONAL as R_FLOAT,
    PROCESS_COVARIANCE_DIAGONAL as Q_FLOAT,
    RBKF_BRANCHES,
    RHO,
    SAMPLING_INTERVAL as DT,
    SEED,
    SIGMA,
    STATE_DIMENSION,
    STEPS,
    TAYLOR_ORDER,
)


INITIAL_STATE = np.asarray(INITIAL_STATE_VALUES, dtype=np.float64)
INITIAL_COV = np.eye(STATE_DIMENSION, dtype=np.float64) * INITIAL_COVARIANCE_DIAGONAL


def sym(matrix: np.ndarray) -> np.ndarray:
    return (matrix + matrix.T) * 0.5


def lorenz_transition(state: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Lorenz transition using the configured truncated Taylor expansion."""
    x = np.asarray(state, dtype=np.float64)
    a = np.array(
        [[-SIGMA, SIGMA, 0.0], [RHO - x[2], -1.0, -x[0]], [x[1], x[0], -BETA]],
        dtype=np.float64,
    )
    adt = a * DT
    transition = np.eye(STATE_DIMENSION, dtype=np.float64)
    power = np.eye(STATE_DIMENSION, dtype=np.float64)
    for order in range(1, TAYLOR_ORDER + 1):
        power = power @ adt
        transition += power / math.factorial(order)
    return transition @ x, transition


def generate_nominal_sequence() -> dict[str, np.ndarray]:
    rng = np.random.default_rng(SEED)
    target = np.empty((STEPS, STATE_DIMENSION), dtype=np.float64)
    process_noise = rng.standard_normal((STEPS, STATE_DIMENSION)) * math.sqrt(Q_FLOAT)
    measurement_noise = rng.standard_normal(
        (STEPS, RBKF_BRANCHES, STATE_DIMENSION)
    ) * math.sqrt(R_FLOAT)
    previous = INITIAL_STATE.copy()
    for step in range(STEPS):
        deterministic, _ = lorenz_transition(previous)
        target[step] = deterministic + process_noise[step]
        previous = target[step]
    measurement = target[:, None, :] + measurement_noise
    return {
        "target": target,
        "process_noise": process_noise,
        "measurement_noise": measurement_noise,
        "measurement": measurement,
    }


def reduced_covariance_float(cov_predict: np.ndarray, branches: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    pz = sym(cov_predict + R_FLOAT * np.eye(STATE_DIMENSION))
    inv_std = 1.0 / np.sqrt(np.diag(pz))
    normalized = pz * inv_std[:, None] * inv_std[None, :]
    np.fill_diagonal(normalized, 1.0)
    reduced = (2.0 / math.pi) * np.arcsin(np.clip(normalized, -1.0, 1.0))
    if branches > 1:
        for feature in range(STATE_DIMENSION):
            self_correlation = cov_predict[feature, feature] / pz[feature, feature]
            cross_branch = (2.0 / math.pi) * math.asin(float(np.clip(self_correlation, -1.0, 1.0)))
            reduced[feature, feature] = (1.0 + (branches - 1) * cross_branch) / branches
    return reduced, inv_std, normalized


def full_reduced_covariance_float(cov_predict: np.ndarray, branches: int) -> np.ndarray:
    """General A*S*A.T construction used only to verify the reduced formula."""
    h_rep = np.tile(np.eye(STATE_DIMENSION), (branches, 1))
    pz = h_rep @ cov_predict @ h_rep.T + R_FLOAT * np.eye(STATE_DIMENSION * branches)
    inv_std = 1.0 / np.sqrt(np.diag(pz))
    normalized = pz * inv_std[:, None] * inv_std[None, :]
    np.fill_diagonal(normalized, 1.0)
    sign_cov = (2.0 / math.pi) * np.arcsin(np.clip(normalized, -1.0, 1.0))
    aggregation = np.zeros(
        (STATE_DIMENSION, STATE_DIMENSION * branches), dtype=np.float64
    )
    for branch in range(branches):
        for feature in range(STATE_DIMENSION):
            aggregation[feature, branch * STATE_DIMENSION + feature] = 1.0 / branches
    return aggregation @ sign_cov @ aggregation.T


def run_float_filter(kind: str, stimulus: dict[str, np.ndarray], branches: int = 1) -> dict[str, np.ndarray]:
    state_post = INITIAL_STATE.copy()
    cov_post = INITIAL_COV.copy()
    names = {
        "f_matrix": (STEPS, STATE_DIMENSION, STATE_DIMENSION),
        "state_predict": (STEPS, STATE_DIMENSION),
        "cov_predict": (STEPS, STATE_DIMENSION, STATE_DIMENSION),
        "threshold": (STEPS, STATE_DIMENSION),
        "branch_bits": (STEPS, branches, STATE_DIMENSION),
        "branch_sum": (STEPS, STATE_DIMENSION),
        "reduced_observation": (STEPS, STATE_DIMENSION),
        "observation_cov": (STEPS, STATE_DIMENSION, STATE_DIMENSION),
        "gain": (STEPS, STATE_DIMENSION, STATE_DIMENSION),
        "state_post": (STEPS, STATE_DIMENSION),
        "cov_post": (STEPS, STATE_DIMENSION, STATE_DIMENSION),
        "determinant": (STEPS,),
    }
    trace = {name: np.zeros(shape, dtype=np.float64) for name, shape in names.items()}
    for step in range(STEPS):
        state_predict, f_matrix = lorenz_transition(state_post)
        cov_predict = sym(
            f_matrix @ cov_post @ f_matrix.T + Q_FLOAT * np.eye(STATE_DIMENSION)
        )
        threshold = state_predict.copy()
        if kind == "ekf":
            observation_cov = sym(cov_predict + R_FLOAT * np.eye(STATE_DIMENSION))
            gain = cov_predict @ np.linalg.inv(observation_cov)
            innovation = stimulus["measurement"][step, 0] - state_predict
            reduced_observation = innovation
            state_post = state_predict + gain @ innovation
            cov_post = sym(cov_predict - gain @ observation_cov @ gain.T)
            bits = np.zeros((branches, STATE_DIMENSION), dtype=np.float64)
            branch_sum = np.zeros(STATE_DIMENSION, dtype=np.float64)
        else:
            measurements = stimulus["measurement"][step, :branches]
            bits = np.where(measurements >= threshold[None, :], 1.0, -1.0)
            branch_sum = np.sum(bits, axis=0)
            reduced_observation = branch_sum / branches
            observation_cov, inv_std, _ = reduced_covariance_float(cov_predict, branches)
            b_diag = math.sqrt(2.0 / math.pi) * inv_std
            gain = cov_predict @ (np.diag(b_diag) @ np.linalg.inv(observation_cov))
            state_post = state_predict + gain @ reduced_observation
            cov_post = cov_predict - gain @ observation_cov @ gain.T
        trace["f_matrix"][step] = f_matrix
        trace["state_predict"][step] = state_predict
        trace["cov_predict"][step] = cov_predict
        trace["threshold"][step] = threshold
        trace["branch_bits"][step] = bits
        trace["branch_sum"][step] = branch_sum
        trace["reduced_observation"][step] = reduced_observation
        trace["observation_cov"][step] = observation_cov
        trace["gain"][step] = gain
        trace["state_post"][step] = state_post
        trace["cov_post"][step] = cov_post
        trace["determinant"][step] = np.linalg.det(observation_cov)
    return trace


def divide_integer_away(numerator: int, denominator: int) -> int:
    negative = (numerator < 0) ^ (denominator < 0)
    magnitude = (abs(int(numerator)) + abs(int(denominator)) // 2) // abs(int(denominator))
    return -magnitude if negative else magnitude


@dataclass
class FixedTrace:
    values: dict[str, np.ndarray]
    stats: ArithmeticStats


class FixedFilter:
    def __init__(self, kind: str, branches: int):
        self.kind = kind
        self.branches = branches
        self.state_post = to_vector(quantize_array(INITIAL_STATE))
        self.cov_post = to_matrix(quantize_array(INITIAL_COV))
        self.stats = ArithmeticStats()
        self.rsqrt_lut = make_rsqrt_lut()
        self.asin_lut = make_asin_lut()

    def step(self, f_input: np.ndarray, measurement_q: np.ndarray) -> dict[str, np.ndarray | int]:
        stats = self.stats
        f_matrix = to_matrix(f_input)
        state_predict = matrix_vector_multiply(f_matrix, self.state_post, stats)
        cov_inner = matrix_multiply(self.cov_post, matrix_transpose(f_matrix), stats)
        cov_unsym = matrix_multiply(f_matrix, cov_inner, stats)
        for feature in range(3):
            cov_unsym[feature][feature] = fx_add(cov_unsym[feature][feature], Q_DIAG, stats)
        cov_predict = matrix_symmetrize(cov_unsym, stats)
        threshold = list(state_predict)

        observation_cov_unsym = [[cov_predict[i][j] for j in range(3)] for i in range(3)]
        for feature in range(3):
            observation_cov_unsym[feature][feature] = fx_add(
                observation_cov_unsym[feature][feature], R_DIAG, stats
            )
        measurement_cov = matrix_symmetrize(observation_cov_unsym, stats)

        if self.kind == "ekf":
            observation_cov = measurement_cov
            inverse, determinant, solver_error = matrix_inverse_3x3(observation_cov, stats)
            gain = matrix_multiply(cov_predict, inverse, stats)
            innovation = [fx_sub(int(measurement_q[0, i]), threshold[i], stats) for i in range(3)]
            reduced_observation = innovation
            branch_bits = np.zeros((self.branches, 3), dtype=np.uint8)
            branch_sum = [0, 0, 0]
        else:
            branch_bits = np.asarray(
                [[1 if int(measurement_q[b, i]) >= threshold[i] else 0 for i in range(3)] for b in range(self.branches)],
                dtype=np.uint8,
            )
            signed_bits = branch_bits.astype(np.int64) * 2 - 1
            branch_sum = [int(item) for item in np.sum(signed_bits, axis=0)]
            reduced_observation = [
                divide_integer_away(branch_sum[i] * ONE, self.branches) for i in range(3)
            ]
            inv_std = [rsqrt_lookup(measurement_cov[i][i], self.rsqrt_lut, stats) for i in range(3)]
            normalized = [[0] * 3 for _ in range(3)]
            for i in range(3):
                for j in range(3):
                    if i == j:
                        normalized[i][j] = ONE
                    else:
                        normalized[i][j] = fx_mul(fx_mul(measurement_cov[i][j], inv_std[i], stats), inv_std[j], stats)
                        normalized[i][j] = min(max(normalized[i][j], -ONE), ONE)
            observation_cov = matrix_symmetrize(
                [[asin_lookup(normalized[i][j], self.asin_lut, stats) for j in range(3)] for i in range(3)], stats
            )
            if self.branches > 1:
                for i in range(3):
                    self_norm = fx_mul(fx_mul(cov_predict[i][i], inv_std[i], stats), inv_std[i], stats)
                    cross = asin_lookup(self_norm, self.asin_lut, stats)
                    observation_cov[i][i] = saturate(
                        divide_integer_away(ONE + (self.branches - 1) * cross, self.branches), stats
                    )
            else:
                for i in range(3):
                    observation_cov[i][i] = ONE
            b_diag = [fx_mul(ALPHA, inv_std[i], stats) for i in range(3)]
            b_matrix = [[b_diag[i] if i == j else 0 for j in range(3)] for i in range(3)]
            inverse, determinant, solver_error = matrix_inverse_3x3(observation_cov, stats)
            gain_inner = matrix_multiply(b_matrix, inverse, stats)
            gain = matrix_multiply(cov_predict, gain_inner, stats)

        correction = matrix_vector_multiply(gain, reduced_observation, stats)
        state_post = [fx_add(state_predict[i], correction[i], stats) for i in range(3)]
        cov_update_inner = matrix_multiply(observation_cov, matrix_transpose(gain), stats)
        cov_correction = matrix_multiply(gain, cov_update_inner, stats)
        cov_post = [[fx_sub(cov_predict[i][j], cov_correction[i][j], stats) for j in range(3)] for i in range(3)]
        if self.kind == "ekf":
            cov_post = matrix_symmetrize(cov_post, stats)
        self.state_post = state_post
        self.cov_post = cov_post
        return {
            "f_matrix": array_from_matrix(f_matrix), "state_predict": np.asarray(state_predict),
            "cov_predict": array_from_matrix(cov_predict), "threshold": np.asarray(threshold),
            "branch_bits": branch_bits, "branch_sum": np.asarray(branch_sum),
            "reduced_observation": np.asarray(reduced_observation),
            "observation_cov": array_from_matrix(observation_cov), "gain": array_from_matrix(gain),
            "state_post": np.asarray(state_post), "cov_post": array_from_matrix(cov_post),
            "determinant": int(determinant), "solver_error": int(solver_error),
        }


def run_fixed_filter(kind: str, stimulus: dict[str, np.ndarray], branches: int = 1) -> FixedTrace:
    fixed = FixedFilter(kind, branches)
    records: list[dict[str, np.ndarray | int]] = []
    measurement_q = quantize_array(stimulus["measurement"][:, :branches])
    for step in range(STEPS):
        _, f_float = lorenz_transition(np.asarray(fixed.state_post, dtype=np.float64) / SCALE)
        f_q = quantize_array(f_float)
        records.append(fixed.step(f_q, measurement_q[step]))
    names = records[0].keys()
    values = {name: np.asarray([record[name] for record in records]) for name in names}
    return FixedTrace(values, fixed.stats)


def metrics(state: np.ndarray, target: np.ndarray) -> dict[str, object]:
    error = np.asarray(state, dtype=np.float64) - target
    state_rmse = np.sqrt(np.mean(error * error, axis=0))
    rmse = float(np.sqrt(np.mean(error * error)))
    nmse = float(10.0 * np.log10(np.sum(error * error) / np.sum(target * target)))
    return {
        "rmse": rmse,
        "state_rmse": [float(item) for item in state_rmse],
        "nmse_db": nmse,
        "error_norm": np.linalg.norm(error, axis=1),
    }


def run_all() -> tuple[dict[str, np.ndarray], dict[str, dict[str, np.ndarray]], dict[str, FixedTrace]]:
    stimulus = generate_nominal_sequence()
    float_traces = {
        "ekf": run_float_filter("ekf", stimulus, 1),
        "bkf_l1": run_float_filter("bkf", stimulus, 1),
        "rbkf_l1": run_float_filter("rbkf", stimulus, 1),
        "rbkf_l8": run_float_filter("rbkf", stimulus, RBKF_BRANCHES),
    }
    fixed_traces = {
        "ekf": run_fixed_filter("ekf", stimulus, 1),
        "bkf_l1": run_fixed_filter("bkf", stimulus, 1),
        "rbkf_l1": run_fixed_filter("rbkf", stimulus, 1),
        "rbkf_l8": run_fixed_filter("rbkf", stimulus, RBKF_BRANCHES),
    }
    return stimulus, float_traces, fixed_traces


def main() -> None:
    ensure_result_dirs()
    output = RESULTS_DIR / "reference"
    output.mkdir(parents=True, exist_ok=True)
    stimulus, float_traces, fixed_traces = run_all()
    np.savez_compressed(output / "stimulus.npz", **stimulus)
    rows: list[dict[str, object]] = []
    error_rows: list[dict[str, object]] = []
    summary: dict[str, object] = {
        "config_sha256": CONFIG_SHA256,
        "seed": SEED,
        "steps": STEPS,
        "algorithms": {},
    }
    for name in float_traces:
        np.savez_compressed(output / f"float_{name}.npz", **float_traces[name])
        np.savez_compressed(output / f"fixed_{name}.npz", **fixed_traces[name].values)
        float_metric = metrics(float_traces[name]["state_post"], stimulus["target"])
        fixed_state = fixed_traces[name].values["state_post"].astype(np.float64) / SCALE
        fixed_metric = metrics(fixed_state, stimulus["target"])
        summary["algorithms"][name] = {
            "float": {key: value for key, value in float_metric.items() if key != "error_norm"},
            "fixed": {key: value for key, value in fixed_metric.items() if key != "error_norm"},
            "fixed_arithmetic": fixed_traces[name].stats.to_dict(),
        }
        for model, metric in (("float", float_metric), ("fixed", fixed_metric)):
            rows.append({"algorithm": name, "model": model, "rmse": metric["rmse"],
                         "rmse_x1": metric["state_rmse"][0], "rmse_x2": metric["state_rmse"][1],
                         "rmse_x3": metric["state_rmse"][2], "nmse_db": metric["nmse_db"]})
            for step, error_norm in enumerate(metric["error_norm"]):
                error_rows.append({"algorithm": name, "model": model, "step": step,
                                   "error_norm": float(error_norm)})
    write_json(output / "summary.json", summary)
    with (RESULTS_DIR / "simulation_metrics.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    with (RESULTS_DIR / "error_norm.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(error_rows[0]))
        writer.writeheader()
        writer.writerows(error_rows)
    print("PASS: generated deterministic float/fixed EKF, BKF L=1, rBKF L=1/L=8 references")


if __name__ == "__main__":
    main()
