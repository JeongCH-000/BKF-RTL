#!/usr/bin/env python3
"""Exercise report failure handling with disposable fixtures, never real RTL outputs."""
from __future__ import annotations

import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np

from common import RESULTS_DIR, write_json
from compare_nominal_rtl import FILES, compare_one


STEPS = 6
ALGORITHM = 'ekf'
STATE_FIELDS = [f'state_{i}_int' for i in range(3)]
COV_FIELDS = [f'cov_{i}{j}_int' for i in range(3) for j in range(3)]
FLAGS = ('overflow', 'numeric_error', 'solver_error')
OUTPUT_FIELDS = ['step', *STATE_FIELDS, *COV_FIELDS, *FLAGS]
CYCLE_FIELDS = ['step', 'start_cycle', 'result_cycle', 'cycles']


def main() -> None:
    with np.load(RESULTS_DIR / 'reference' / f'fixed_{ALGORITHM}.npz') as model:
        states = model['state_post'][:STEPS].copy()
        covariances = model['cov_post'][:STEPS].copy()
    rows = []
    cycles = []
    for index in range(STEPS):
        row = dict(step=index)
        row.update(zip(STATE_FIELDS, (int(value) for value in states[index])))
        row.update(zip(COV_FIELDS, (int(value) for value in covariances[index].flat)))
        row.update({flag: 0 for flag in FLAGS})
        rows.append(row)
        # This validator fixture needs internally valid cycle rows; it does not
        # claim to measure a real RTL transaction latency.
        cycles.append(dict(step=index, start_cycle=10*index,
                           result_cycle=10*index+9, cycles=9))

    results = []
    with TemporaryDirectory(prefix='bkf_bitwidth_validation_') as temporary:
        directory = Path(temporary)

        def check(name, test_rows, test_cycles, status, first_step=None):
            for filename, fields, payload in (
                (FILES[ALGORITHM], OUTPUT_FIELDS, test_rows),
                (f'cycle_counts_{ALGORITHM}.csv', CYCLE_FIELDS, test_cycles),
            ):
                with (directory / filename).open('w', newline='') as handle:
                    writer = csv.DictWriter(handle, fieldnames=fields)
                    writer.writeheader()
                    writer.writerows(payload)
            report = compare_one(ALGORITHM, directory, STEPS)
            assert report['implementation_status'] == status, (name, report)
            assert report['first_failure_step'] == first_step, (name, report)
            results.append(dict(case=name, expected_status=status,
                                first_failure_step=first_step, result='PASS'))
            print(f'PASS: validation {name}: {status}, first_failure_step={first_step}')
            return report

        check('complete_fixture', rows, cycles, 'PASS')
        check('truncated_outputs', rows[:-1], cycles[:-1], 'INCOMPLETE', STEPS-1)

        changed = [dict(row) for row in rows]
        changed[2][STATE_FIELDS[0]] = 'x'
        check('x_state', changed, cycles, 'FAIL', 2)

        changed = [dict(row) for row in rows]
        changed[4][COV_FIELDS[0]] = 'z'
        check('z_covariance', changed, cycles, 'FAIL', 4)

        changed = [dict(row) for row in rows]
        changed[3]['solver_error'] = 2
        check('invalid_flag', changed, cycles, 'FAIL', 3)

        changed = [dict(row) for row in rows]
        changed[4]['step'] = 3
        check('duplicate_step', changed, cycles, 'FAIL', 4)

        changed = [dict(row) for row in rows]
        changed[1][STATE_FIELDS[0]] += 1
        check('state_mismatch', changed, cycles, 'FAIL', 1)

        check('missing_cycle_row', rows, cycles[:-1], 'FAIL', STEPS-1)
        check('no_cycle_rows', rows, [], 'FAIL', 0)

        changed = [dict(row) for row in rows]
        for index, flag in enumerate(FLAGS):
            changed[index][flag] = 1
        report = check('numeric_flags_preserve_implementation_pass', changed, cycles, 'PASS')
        assert report['numerical_status'] == 'FLAGS_OR_NEGATIVE_DIAGONAL', report
        for flag in FLAGS:
            assert report[f'{flag}_count'] == 1, report
            assert report[f'first_{flag}_step'] == FLAGS.index(flag), report

    target = RESULTS_DIR / 'bitwidth' / 'validation_failure_checks.json'
    write_json(target, results)
    print(f'PASS: {len(results)} disposable report-validation cases; {target.relative_to(RESULTS_DIR)}')


if __name__ == '__main__':
    main()
