#!/usr/bin/env python3
"""Verify generalized W=24/F=16 against a fresh isolated latest-source run.

Usage: python/check_q8_16_regression.py --baseline BASELINE --generalized NEW
       [--original SOURCE] [--output REPORT.json]
All input projects are read-only. Reports are written only to --output and the
current project's results/bitwidth. Numeric array contents, not NPZ container
bytes or generated metadata timestamps, define numerical reproducibility.
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import re

import numpy as np

from common import ROOT, array_checksum, file_checksum, write_json

ALGORITHMS = ("ekf", "bkf_l1", "rbkf_l1", "rbkf_l8")
REFERENCE_FILES = ("stimulus",) + tuple(f"{kind}_{name}" for kind in ("float", "fixed") for name in ALGORITHMS)


def compare_npz(left: Path, right: Path) -> dict:
    result = {"baseline": str(left), "candidate": str(right), "status": "PASS", "arrays": {},
              "compared_arrays": 0, "compared_elements": 0, "first_failure_step": None}
    if not left.is_file() or not right.is_file():
        result.update(status="INCOMPLETE", reason="missing baseline or candidate NPZ")
        return result
    with np.load(left, allow_pickle=False) as expected, np.load(right, allow_pickle=False) as actual:
        result["new_diagnostic_arrays"] = sorted(set(actual.files) - set(expected.files))
        for name in sorted(expected.files):
            a = expected[name]
            entry = {"status": "PASS", "shape": list(a.shape), "dtype": str(a.dtype),
                     "baseline_sha256": array_checksum([(name, a)]), "first_mismatch_index": None}
            if name not in actual:
                entry.update(status="FAIL", reason="baseline array missing from candidate")
            else:
                b = actual[name]
                entry["candidate_sha256"] = array_checksum([(name, b)])
                if a.shape != b.shape or a.dtype != b.dtype:
                    entry.update(status="FAIL", reason="shape or dtype differs", candidate_shape=list(b.shape), candidate_dtype=str(b.dtype))
                else:
                    result["compared_arrays"] += 1
                    result["compared_elements"] += int(a.size)
                    unequal = np.not_equal(a, b)
                    if np.any(unequal):
                        index = tuple(int(v) for v in np.argwhere(unequal)[0])
                        entry.update(status="FAIL", reason="array content differs", first_mismatch_index=list(index),
                                     baseline_value=a[index].item(), candidate_value=b[index].item(),
                                     mismatch_count=int(np.count_nonzero(unequal)),
                                     max_abs_difference=float(np.max(np.abs(a.astype(np.float64) - b.astype(np.float64)))))
                        if index and result["first_failure_step"] is None:
                            result["first_failure_step"] = index[0]
            if entry["status"] != "PASS":
                result["status"] = "FAIL"
            result["arrays"][name] = entry
    return result


def words(path: Path) -> list[int]:
    clean = re.sub(r"//[^\n]*|/\*.*?\*/", "", path.read_text(encoding="ascii"), flags=re.S)
    return [int(token, 16) for token in clean.split()]


def compare_vector_words(baseline: Path, generalized: Path) -> dict:
    files = sorted({*(baseline / "rtl/nonlinear").glob("*.hex"),
                    *(baseline / "vectors/nominal").rglob("*.mem"),
                    *(baseline / "tb/vectors").glob("*.hex")})
    result = {"status": "PASS", "compared_files": 0, "compared_words": 0, "files": {},
              "comparison": "Every baseline LUT, nominal MEM and unit HEX numeric word; metadata intentionally excluded"}
    for left in files:
        relative = left.relative_to(baseline)
        right = generalized / relative
        entry = {"status": "PASS", "baseline_file_sha256": file_checksum(left), "first_failure_word": None}
        if not right.is_file():
            entry.update(status="INCOMPLETE", reason="missing regenerated vector")
        else:
            a, b = words(left), words(right)
            entry.update(baseline_words=len(a), candidate_words=len(b), candidate_file_sha256=file_checksum(right))
            result["compared_files"] += 1
            result["compared_words"] += min(len(a), len(b))
            if len(a) != len(b):
                entry.update(status="FAIL", reason="word count differs", first_failure_word=min(len(a), len(b)))
            for index, (expected, actual) in enumerate(zip(a, b)):
                if expected != actual:
                    entry.update(status="FAIL", reason="numeric packed word differs", first_failure_word=index,
                                 baseline_word=hex(expected), candidate_word=hex(actual))
                    break
        if entry["status"] != "PASS":
            result["status"] = "FAIL"
        result["files"][str(relative)] = entry
    if not files:
        result.update(status="INCOMPLETE", reason="no baseline vectors")
    return result


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        return reader.fieldnames or [], list(reader)


def compare_csv(left: Path, right: Path, steps: int) -> dict:
    result = {"status": "PASS", "requested_steps": steps, "baseline_completed_steps": 0,
              "completed_steps": 0, "first_failure_step": None, "compared_cells": 0,
              "baseline": str(left), "candidate": str(right)}
    try:
        a_fields, a = read_csv(left)
        b_fields, b = read_csv(right)
        result.update(baseline_completed_steps=len(a), completed_steps=len(b),
                      compared_columns=sorted(set(a_fields) & set(b_fields)),
                      candidate_added_columns=sorted(set(b_fields) - set(a_fields)))
        missing_fields = sorted(set(a_fields) - set(b_fields))
        if missing_fields:
            raise ValueError(f"candidate omits baseline columns: {missing_fields}")
        for label, rows in (("baseline", a), ("candidate", b)):
            if len(rows) != steps:
                result["first_failure_step"] = min(len(rows), steps)
                raise ValueError(f"{label} completed {len(rows)}/{steps} rows")
            if [int(row["step"]) for row in rows] != list(range(steps)):
                raise ValueError(f"{label} has unordered/duplicate/missing step indexes")
        for step, (expected, actual) in enumerate(zip(a, b)):
            for field in result["compared_columns"]:
                av, bv = int(expected[field]), int(actual[field])
                result["compared_cells"] += 1
                if av != bv:
                    result.update(first_failure_step=step, first_failure_field=field, baseline_value=av, candidate_value=bv)
                    raise ValueError("common RTL CSV field differs")
        if "cycles" in a_fields:
            result["cycles_per_update_min"] = min(int(row["cycles"]) for row in b)
            result["cycles_per_update_max"] = max(int(row["cycles"]) for row in b)
        result["candidate_flag_counts"] = {}
        for field in ("overflow", "numeric_error", "solver_error"):
            if field in b_fields:
                values = [int(row[field]) for row in b]
                if any(value not in (0, 1) for value in values):
                    raise ValueError(f"candidate has unknown or invalid {field}")
                result["candidate_flag_counts"][field] = sum(values)
        if any(field in result["candidate_added_columns"] for field in ("overflow", "numeric_error", "solver_error")):
            result["flag_provenance"] = "The latest original testbench and fresh isolated baseline CSV do not export these flags; candidate actual flags are counted. Baseline testbench error assertions are documented separately; a missing CSV field is not claimed as a CSV comparison."
    except (OSError, KeyError, ValueError) as error:
        result.update(status="INCOMPLETE" if isinstance(error, OSError) else "FAIL", reason=str(error))
    return result


def run_directory(root: Path, algorithm: str, steps: int, baseline: bool) -> Path:
    if not baseline:
        return root / "results/bitwidth/runs" / f"{algorithm}_{steps}"
    cli_name = "bkf" if algorithm == "bkf_l1" else algorithm
    archived = root / "results/bitwidth" / f"{cli_name}_{steps}"
    return archived if archived.is_dir() else root / "results"


def test_status(root: Path, algorithm: str, steps: int, baseline: bool) -> dict:
    path = root / "results/bitwidth/test_status.json"
    name = ("bkf" if algorithm == "bkf_l1" and baseline else algorithm) + f"_{steps}"
    if not path.is_file():
        return {"status": "INCOMPLETE", "reason": "missing test_status.json", "test": name}
    records = json.loads(path.read_text())
    found = [record for record in records if record["test"] == name]
    if len(found) != 1:
        return {"status": "INCOMPLETE", "reason": "missing or duplicate test execution record", "test": name}
    record = found[0]
    return {**record, "status": "PASS" if record.get("returncode") == 0 and record.get("status", "PASS") == "PASS" else "FAIL"}


def compare_original_source(original: Path, baseline: Path) -> dict:
    references = {
        name: compare_npz(original / f"results/reference/{name}.npz", baseline / f"results/reference/{name}.npz")
        if (original / f"results/reference/{name}.npz").is_file()
        else {"status": "N/A", "reason": "No stored reference in source; fresh isolated baseline is authoritative"}
        for name in REFERENCE_FILES
    }
    source_files = {}
    for family, patterns in (("rtl", ("*.v", "*.vh")), ("python", ("*.py",)), ("config", ("*.yaml",)), ("constraints", ("*.xdc",))):
        for pattern in patterns:
            for left in sorted((original / family).rglob(pattern)):
                relative = left.relative_to(original)
                right = baseline / relative
                source_files[str(relative)] = {
                    "original_sha256": file_checksum(left),
                    "baseline_sha256": file_checksum(right) if right.is_file() else None,
                    "status": "PASS" if right.is_file() and file_checksum(left) == file_checksum(right) else "MISMATCH",
                }
    mismatch_files = [name for name, result in source_files.items() if result["status"] != "PASS"]
    return {
        "status": "PASS" if all(result["status"] in ("PASS", "N/A") for result in references.values()) and not mismatch_files else "PROVENANCE_MISMATCH",
        "source_root": str(original), "fresh_isolated_baseline_root": str(baseline),
        "reference_label": "baseline_q8_16", "reference_arrays": references,
        "source_files": source_files, "source_mismatch_files": mismatch_files,
        "note": "Source directories are read-only; available source NPZ contents are independently compared to fresh isolated output; absent stored results are not required for a clean checkout. Prior stored results are never relabeled as new-format RTL results.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--generalized", required=True, type=Path)
    parser.add_argument("--original", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "results/bitwidth/q8_16_generalization_regression.json")
    args = parser.parse_args()
    baseline, generalized = args.baseline.resolve(), args.generalized.resolve()
    result = {"status": "PASS", "format": {"signed_width": 24, "fractional_bits": 16},
              "baseline_root": str(baseline), "generalized_root": str(generalized),
              "reference_label": "baseline_q8_16", "failures": []}
    # Check actual generated format, independent of this checker's host project.
    header = (generalized / "rtl/common/fx_q8_16_defs.vh").read_text()
    for macro, expected in (("WIDTH", 24), ("FRAC", 16)):
        found = re.search(rf"`define\s+FX_Q8_16_{macro}\s+(\d+)", header)
        if found is None or int(found.group(1)) != expected:
            result["failures"].append(f"generalized RTL {macro} is not {expected}")
    result["reference_arrays"] = {name: compare_npz(baseline / f"results/reference/{name}.npz", generalized / f"results/reference/{name}.npz") for name in REFERENCE_FILES}
    for name, record in result["reference_arrays"].items():
        if record["status"] != "PASS":
            result["failures"].append(f"reference {name}: {record['status']}")
    result["regenerated_vectors"] = compare_vector_words(baseline, generalized)
    if result["regenerated_vectors"]["status"] != "PASS":
        result["failures"].append("regenerated vector comparison failed")
    result["algorithms"] = {}
    for algorithm in ALGORITHMS:
        fixed = result["reference_arrays"][f"fixed_{algorithm}"]
        floating = result["reference_arrays"][f"float_{algorithm}"]
        baseline_tb_name = "tb_ekf_full.sv" if algorithm == "ekf" else ("tb_bkf_full.sv" if algorithm == "bkf_l1" else "tb_rbkf_full.sv")
        baseline_tb = baseline / "tb/integration" / baseline_tb_name
        baseline_tb_text = baseline_tb.read_text() if baseline_tb.is_file() else ""
        baseline_assertion = re.search(r"if\s*\(overflow_flag\s*\|\|\s*numeric_error\s*\|\|\s*solver_error\)\s*(?:fail\(|fail_mismatch\()", baseline_tb_text) is not None
        item = {"status": "PASS", "first_failure_step": None,
                "baseline_flag_assertion": {
                    "present": baseline_assertion, "source": str(baseline_tb),
                    "contract": "Fresh original testbench fails the test if any overflow/numeric_error/solver_error is asserted at a checked update. This assertion evidence is distinct from exported CSV flag counts.",
                },
                "fixed_arrays_compared": fixed["compared_arrays"], "fixed_elements_compared": fixed["compared_elements"],
                "float_arrays_compared": floating["compared_arrays"], "float_elements_compared": floating["compared_elements"], "runs": {}}
        for steps in (1, 500):
            left = run_directory(baseline, algorithm, steps, True)
            right = run_directory(generalized, algorithm, steps, False)
            run = {
                "baseline_test": test_status(baseline, algorithm, steps, True),
                "generalized_test": test_status(generalized, algorithm, steps, False),
                "rtl_outputs": compare_csv(left / f"rtl_{algorithm}_outputs.csv", right / f"rtl_{algorithm}_outputs.csv", steps),
                "cycles": compare_csv(left / f"cycle_counts_{algorithm}.csv", right / f"cycle_counts_{algorithm}.csv", steps),
            }
            run["status"] = "PASS" if all(record["status"] == "PASS" for record in run.values()) else "FAIL"
            item["runs"][str(steps)] = run
            if run["status"] != "PASS":
                item["status"] = "FAIL"
                failures = [record.get("first_failure_step") for record in run.values() if isinstance(record, dict) and record.get("first_failure_step") is not None]
                item["first_failure_step"] = min(failures) if failures else None
        for reference in (fixed, floating):
            if reference["status"] != "PASS":
                item.update(status="FAIL", first_failure_step=reference["first_failure_step"])
        if item["status"] != "PASS":
            result["failures"].append(f"algorithm {algorithm} comparison failed")
        result["algorithms"][algorithm] = item
    generated_status_path = generalized / "results/bitwidth/test_status.json"
    records = json.loads(generated_status_path.read_text()) if generated_status_path.is_file() else []
    result["generalized_test_status"] = records
    required_tests = {"format_generate", "nominal_models", "generate_luts", "generate_nominal_vectors", "generate_unit_vectors", "reference_tests", "lint", "pipeline_structure", "unit_tests", "independent_arithmetic", "validation_failure_checks", "compare_nominal_rtl", "local_report"}
    for name in required_tests:
        record = next((item for item in records if item["test"] == name), None)
        if record is None or record.get("status") != "PASS":
            result["failures"].append(f"generalized required test {name} missing/failed")
    if args.original:
        result["original_source_provenance"] = compare_original_source(args.original.resolve(), baseline)
        if result["original_source_provenance"]["status"] != "PASS":
            result["failures"].append("original-source provenance differs from fresh baseline; inspect explicit mismatch records")
    result["status"] = "FAIL" if result["failures"] else "PASS"
    result["summary"] = {
        "reference_arrays_compared": sum(item["compared_arrays"] for item in result["reference_arrays"].values()),
        "reference_elements_compared": sum(item["compared_elements"] for item in result["reference_arrays"].values()),
        "regenerated_vector_files_compared": result["regenerated_vectors"]["compared_files"],
        "regenerated_vector_words_compared": result["regenerated_vectors"]["compared_words"],
        "rtl_runs_compared": len(ALGORITHMS) * 2,
    }
    write_json(args.output, result)
    print(f"{result['status']}: Q8.16 generalized/source regression {json.dumps(result['summary'])}")
    for failure in result["failures"]:
        print(f"FAIL: {failure}")
    if result["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
