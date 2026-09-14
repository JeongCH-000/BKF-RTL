#!/usr/bin/env python3
"""Read-only structural comparison against the latest source RTL project.

This bounded static audit checks FSM declarations/transitions, selected clock
and ready/valid assignments, register names, ordered sequential destinations,
and rounding/saturation call placement. It supplements executable regression;
it is not a formal equivalence proof. Generated constants are validated by
nominal_config.py, not this structural checker.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def selected_controls(text: str) -> list[str]:
    expression = (r"localparam.*\bST_|\bstate <=|always @\(posedge|"
                  r"assign (request_ready|result_valid|cfg_ready|model_ready|"
                  r"threshold_valid|observation_ready|busy|done|fsm_state|divider_start)")
    return [line.strip() for line in text.splitlines() if re.search(expression, line)]


def sequential_destinations(text: str) -> list[str]:
    return re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?)\s*<=", text)


def register_names(text: str) -> list[str]:
    return re.findall(r"^\s*reg\s+(?:signed\s+)?(?:\[[^\]]+\]\s*)?"
                      r"([A-Za-z_][A-Za-z0-9_]*)", text, re.MULTILINE)


def arithmetic_calls(text: str) -> list[str]:
    return re.findall(r"\b(round_sat48|round_sat50|overflow48|overflow50|add_sat24|"
                      r"sub_sat24|add_overflow24|sub_overflow24|average24)\s*\(", text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True,
                        help="Original source project root, opened read-only")
    parser.add_argument("--output", type=Path,
                        default=ROOT / "results" / "bitwidth" / "audit" / "rtl_structure.json")
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if source == ROOT:
        parser.error("--source must be an independent original project")
    if output.is_relative_to(source):
        parser.error("Refusing to write the audit output inside the read-only source project")
    if not (source / "rtl").is_dir():
        parser.error("--source must contain rtl/")
    files = sorted((ROOT / "rtl").rglob("*.v"))
    files.append(ROOT / "rtl" / "common" / "fx_q8_16_functions.vh")
    records = []
    for current in files:
        relative = current.relative_to(ROOT)
        original = source / relative
        record = {"file": str(relative)}
        if not original.is_file():
            record.update({"status": "FAIL", "error": "Source RTL file is missing"})
            records.append(record)
            continue
        before, after = original.read_text(), current.read_text()
        record["source_sha256"] = digest(original)
        record["current_sha256"] = digest(current)
        checks = {
            "selected_control_lines_identical": selected_controls(before) == selected_controls(after),
            "nonblocking_destinations_identical": sequential_destinations(before) == sequential_destinations(after),
            "register_names_identical": register_names(before) == register_names(after),
            "arithmetic_call_order_identical": arithmetic_calls(before) == arithmetic_calls(after),
        }
        record["checks"] = checks
        record["status"] = "PASS" if all(checks.values()) else "FAIL"
        record["changes"] = [
            {"kind": tag, "original_lines": [i1 + 1, i2], "current_lines": [j1 + 1, j2]}
            for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(
                None, before.splitlines(), after.splitlines()).get_opcodes()
            if tag != "equal"
        ]
        records.append(record)
    # Detect accidental module removal/addition, not only changes in shared files.
    source_modules = sorted(str(p.relative_to(source)) for p in (source / "rtl").rglob("*.v"))
    current_modules = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "rtl").rglob("*.v"))
    same_modules = source_modules == current_modules
    passed = same_modules and all(record["status"] == "PASS" for record in records)
    report = {"status": "PASS" if passed else "FAIL", "source_project": str(source),
              "current_project": str(ROOT), "module_file_set_identical": same_modules,
              "module_count": len(current_modules), "files_checked": len(records),
              "scope": __doc__.strip(), "files": records}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"{report['status']}: static RTL structure, {len(current_modules)} modules, {output}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
