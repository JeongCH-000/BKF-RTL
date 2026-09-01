#!/usr/bin/env python3
"""Generate all nominal readmemh vectors from the integer reference traces."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np

from common import ROOT, file_checksum, write_json
from fixed_math import (
    FRAC,
    WIDTH,
    array_from_matrix,
    matrix_multiply,
    matrix_transpose,
    quantize_array,
    to_matrix,
)
from nominal_models import INITIAL_COV, INITIAL_STATE, RBKF_BRANCHES, SCALE, SEED, STEPS
from nominal_config import CONFIG_SHA256, STATE_DIMENSION


VECTOR_ROOT = ROOT / "vectors" / "nominal"


def pack(values: np.ndarray, width: int) -> int:
    word = 0
    mask = (1 << width) - 1
    for index, value in enumerate(np.asarray(values).reshape(-1)):
        word |= (int(value) & mask) << (index * width)
    return word


def write_mem(path: Path, array: np.ndarray, width: int = WIDTH) -> None:
    values = np.asarray(array)
    records = values.reshape(values.shape[0], -1)
    digits = (records.shape[1] * width + 3) // 4
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{pack(record, width):0{digits}x}" for record in records]
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def add_file(manifest: dict[str, object], relative: str, array: np.ndarray, width: int = WIDTH) -> None:
    path = VECTOR_ROOT / relative
    write_mem(path, array, width)
    manifest[relative] = {
        "records": int(array.shape[0]),
        "elements_per_record": int(np.asarray(array).reshape(array.shape[0], -1).shape[1]),
        "element_width": width,
        "sha256": file_checksum(path),
    }


def covariance_inner_trace(trace: np.lib.npyio.NpzFile) -> np.ndarray:
    """Recreate the existing P_post * F.T quantization boundary for checking."""
    result = np.empty_like(trace["cov_predict"])
    previous_covariance = quantize_array(INITIAL_COV)
    for step in range(STEPS):
        inner = matrix_multiply(
            to_matrix(previous_covariance),
            matrix_transpose(to_matrix(trace["f_matrix"][step])),
        )
        result[step] = array_from_matrix(inner)
        previous_covariance = trace["cov_post"][step]
    return result


def main() -> None:
    reference = ROOT / "results" / "reference"
    summary_path = reference / "summary.json"
    if not (reference / "stimulus.npz").is_file() or not summary_path.is_file():
        raise SystemExit("Run python/nominal_models.py first")
    reference_summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if reference_summary.get("config_sha256") != CONFIG_SHA256:
        raise SystemExit(
            "Reference artifacts do not match config/nominal.yaml; "
            "run python/nominal_models.py first"
        )
    stimulus = np.load(reference / "stimulus.npz")
    fixed = {name: np.load(reference / f"fixed_{name}.npz") for name in ("ekf", "bkf_l1", "rbkf_l1", "rbkf_l8")}
    manifest: dict[str, object] = {}

    add_file(manifest, "common/ground_truth.mem", quantize_array(stimulus["target"]))
    add_file(manifest, "common/process_noise.mem", quantize_array(stimulus["process_noise"]))
    add_file(manifest, "common/init_state.mem", quantize_array(INITIAL_STATE)[None, :])
    add_file(manifest, "common/init_cov.mem", quantize_array(INITIAL_COV)[None, :, :])

    measurement_q = quantize_array(stimulus["measurement"])
    for name in ("ekf", "bkf_l1", "rbkf_l1", "rbkf_l8"):
        trace = fixed[name]
        add_file(manifest, f"{name}/f_matrix.mem", trace["f_matrix"])
        if name == "ekf":
            add_file(
                manifest,
                "ekf/expected_cov_inner.mem",
                covariance_inner_trace(trace),
            )
        add_file(manifest, f"{name}/expected_cov_predict.mem", trace["cov_predict"])
        add_file(manifest, f"{name}/expected_state.mem", trace["state_post"])
        add_file(manifest, f"{name}/expected_cov.mem", trace["cov_post"])
        add_file(manifest, f"{name}/expected_gain.mem", trace["gain"])
        add_file(manifest, f"{name}/expected_determinant.mem", trace["determinant"][:, None])
        if name == "ekf":
            add_file(manifest, "ekf/measurement.mem", measurement_q[:, 0, :])
            add_file(manifest, "ekf/expected_innovation_cov.mem", trace["observation_cov"])
        else:
            add_file(manifest, f"{name}/expected_threshold.mem", trace["threshold"])
            add_file(manifest, f"{name}/expected_reduced_observation.mem", trace["reduced_observation"])
            add_file(manifest, f"{name}/expected_reduced_cov.mem", trace["observation_cov"])
            add_file(manifest, f"{name}/branch_observation_bits.mem", trace["branch_bits"], 1)
            branches = RBKF_BRANCHES if name == "rbkf_l8" else 1
            add_file(manifest, f"{name}/measurement.mem", measurement_q[:, :branches, :])

    digest = hashlib.sha256()
    for relative in sorted(manifest):
        digest.update(relative.encode("utf-8"))
        digest.update(bytes.fromhex(manifest[relative]["sha256"]))
    metadata = {
        "schema_version": 2,
        "config_sha256": CONFIG_SHA256,
        "seed": SEED,
        "steps": STEPS,
        "branch_order": (
            f"branch-major: flattened index = branch*{STATE_DIMENSION} + feature"
        ),
        "matrix_order": (
            f"row-major, element zero in least-significant {WIDTH}-bit slice"
        ),
        "q_format": f"signed Q{WIDTH - FRAC}.{FRAC}",
        "observation_encoding": "one bit: 1=+1, 0=-1; equality maps to +1",
        "files": manifest,
        "vector_set_sha256": digest.hexdigest(),
    }
    write_json(VECTOR_ROOT / "common" / "metadata.json", metadata)
    print(f"PASS: generated {len(manifest)} nominal vector files ({digest.hexdigest()})")


if __name__ == "__main__":
    main()
