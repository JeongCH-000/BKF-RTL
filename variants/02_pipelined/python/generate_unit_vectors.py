#!/usr/bin/env python3
"""Generate deterministic matrix/solver vectors for independent RTL unit tests."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from common import RESULTS_DIR, ROOT, file_checksum, write_json
from fixed_math import (
    ONE,
    WIDTH,
    ArithmeticStats,
    matrix_inverse_3x3,
    matrix_multiply,
    quantize_array,
    to_matrix,
)
from nominal_config import CONFIG_SHA256
from nominal_models import STEPS


OUT = ROOT / "tb" / "vectors"


def pack_record(values: np.ndarray, element_width: int) -> int:
    packed = 0
    mask = (1 << element_width) - 1
    for index, value in enumerate(values):
        packed |= (int(value) & mask) << (index * element_width)
    return packed


def write_packed(path: Path, arrays: list[np.ndarray], element_width: int = WIDTH) -> None:
    elements = int(np.asarray(arrays[0]).size)
    digits = (elements * element_width + 3) // 4
    with path.open("w", encoding="ascii") as stream:
        for array in arrays:
            stream.write(f"{pack_record(np.asarray(array).reshape(-1), element_width):0{digits}x}\n")


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
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(0xB0_55_6A)
    identity = np.eye(3, dtype=np.int64) * ONE
    zeros = np.zeros((3, 3), dtype=np.int64)

    matrix_cases: list[tuple[np.ndarray, np.ndarray]] = [(identity, identity), (identity, zeros), (zeros, identity)]
    for case_index in range(61):
        a = rng.integers(-2 * ONE, 2 * ONE + 1, size=(3, 3), dtype=np.int64)
        b = rng.integers(-2 * ONE, 2 * ONE + 1, size=(3, 3), dtype=np.int64)
        if case_index % 7 == 0:
            a = identity.copy()
        if case_index % 11 == 0:
            b = identity.copy()
        matrix_cases.append((a, b))

    mat_a: list[np.ndarray] = []
    mat_b: list[np.ndarray] = []
    mat_y: list[np.ndarray] = []
    mat_flags: list[np.ndarray] = []
    for a, b in matrix_cases:
        stats = ArithmeticStats()
        y = np.asarray(matrix_multiply(to_matrix(a), to_matrix(b), stats), dtype=np.int64)
        mat_a.append(a)
        mat_b.append(b)
        mat_y.append(y)
        mat_flags.append(np.asarray([int(stats.saturation_count != 0)], dtype=np.int64))

    fixed = np.load(RESULTS_DIR / "reference" / "fixed_bkf_l1.npz")
    inverse_inputs = [identity]
    inverse_inputs.extend(
        fixed["observation_cov"][index].astype(np.int64)
        for index in np.linspace(0, STEPS - 1, min(STEPS, 20), dtype=int)
    )
    inverse_inputs.extend(
        [
            np.ones((3, 3), dtype=np.int64) * ONE,
            quantize_array(np.full((3, 3), 0.9999) + np.eye(3) * 0.0001),
            quantize_array(np.full((3, 3), 0.9990) + np.eye(3) * 0.0010),
            quantize_array(np.diag([0.5, 2.0, 3.0])),
        ]
    )
    inv_y: list[np.ndarray] = []
    inv_det: list[np.ndarray] = []
    inv_flags: list[np.ndarray] = []
    for matrix in inverse_inputs:
        stats = ArithmeticStats()
        inverse, determinant, solver = matrix_inverse_3x3(to_matrix(matrix), stats)
        inv_y.append(np.asarray(inverse, dtype=np.int64))
        inv_det.append(np.asarray([determinant], dtype=np.int64))
        inv_flags.append(np.asarray([int(stats.saturation_count != 0) | (int(solver) << 1)], dtype=np.int64))

    files = {
        "unit_matmul_a.hex": mat_a,
        "unit_matmul_b.hex": mat_b,
        "unit_matmul_y.hex": mat_y,
        "unit_matmul_flags.hex": mat_flags,
        "unit_inverse_input.hex": inverse_inputs,
        "unit_inverse_y.hex": inv_y,
        "unit_inverse_det.hex": inv_det,
        "unit_inverse_flags.hex": inv_flags,
    }
    for name, arrays in files.items():
        write_packed(OUT / name, arrays, 2 if "flags" in name else WIDTH)

    manifest = {
        "matmul_cases": len(matrix_cases),
        "inverse_cases": len(inverse_inputs),
        "includes_singular": True,
        "includes_near_singular": True,
        "files": {name: file_checksum(OUT / name) for name in sorted(files)},
    }
    write_json(OUT / "unit_vector_manifest.json", manifest)
    print(f"Generated {len(matrix_cases)} matmul and {len(inverse_inputs)} inverse unit cases")


if __name__ == "__main__":
    main()
