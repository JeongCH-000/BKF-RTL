"""Shared paths and deterministic serialization helpers."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
RESULTS_DIR = ROOT / "results"


def ensure_result_dirs() -> None:
    for relative in (
        "baseline",
        "fixed",
        "rtl",
        "plots",
        "waveform",
        "synthesis",
    ):
        (RESULTS_DIR / relative).mkdir(parents=True, exist_ok=True)


def array_checksum(items: Iterable[tuple[str, np.ndarray]]) -> str:
    """Hash array names, shapes, dtypes, and C-order bytes deterministically."""
    digest = hashlib.sha256()
    for name, value in items:
        array = np.ascontiguousarray(value)
        digest.update(name.encode("utf-8"))
        digest.update(str(array.shape).encode("ascii"))
        digest.update(array.dtype.str.encode("ascii"))
        digest.update(array.tobytes(order="C"))
    return digest.hexdigest()


def file_checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
