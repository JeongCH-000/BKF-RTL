#!/usr/bin/env python3
"""Compare RTL with the current integer model; separate agreement from quality.
RTL flagged updates and Python internal saturation events are different metrics.
"""
from __future__ import annotations
import argparse
import csv
import re
from pathlib import Path
import numpy as np
from common import RESULTS_DIR, write_json
from fixed_math import WIDTH, FRAC

FILES = {'ekf': 'rtl_ekf_outputs.csv', 'bkf_l1': 'rtl_bkf_l1_outputs.csv',
         'rbkf_l1': 'rtl_rbkf_l1_outputs.csv', 'rbkf_l8': 'rtl_rbkf_l8_outputs.csv'}


def csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline='', encoding='utf-8') as stream:
        return list(csv.DictReader(stream))


def load_csv(path: Path) -> tuple[np.ndarray, np.ndarray]:
    rows = csv_rows(path)
    states, covariances = [], []
    for index, row in enumerate(rows):
        try:
            states.append([int(row[f'state_{i}_int']) for i in range(3)])
            covariances.append([[int(row[f'cov_{i}{j}_int']) for j in range(3)] for i in range(3)])
        except (ValueError, KeyError, TypeError) as error:
            raise ValueError(f'invalid, missing, or X/Z data at step={index}: {error}') from error
    state = np.asarray(states, dtype=np.int64).reshape(-1, 3)
    cov = np.asarray(covariances, dtype=np.int64).reshape(-1, 3, 3)
    return state, cov


def compare_one(algorithm: str, directory: Path = RESULTS_DIR, steps: int = 500) -> dict:
    record = dict(algorithm=algorithm, W=WIDTH, F=FRAC, requested_steps=steps,
                  completed_steps=0, implementation_status='INCOMPLETE',
                  numerical_status='NOT_EVALUATED', first_failure_step=None, failure_reason='',
                  overflow_count=None, solver_error_count=None, numeric_error_count=None,
                  state_bit_exact_rate=None, cov_bit_exact_rate=None,
                  state_max_abs_code_diff=None, cov_max_abs_code_diff=None,
                  negative_covariance_diagonal_count=None, covariance_symmetry_max_lsb=None,
                  cycles_per_update_min=None, cycles_per_update_max=None)
    try:
        rows = csv_rows(directory / FILES[algorithm])
        record['completed_steps'] = len(rows)
        state, cov = load_csv(directory / FILES[algorithm])
        for index, row in enumerate(rows):
            if row.get('step') != str(index):
                raise ValueError(f'duplicate, missing, or out-of-order row at step={index}')
        if len(rows) > steps:
            raise ValueError(f'extra output at step={steps}: {len(rows)} > {steps}')
        for field, count_key in (('overflow', 'overflow_count'), ('solver_error', 'solver_error_count'), ('numeric_error', 'numeric_error_count')):
            flags = []
            for index, row in enumerate(rows):
                if row.get(field) not in ('0', '1'):
                    raise ValueError(f'invalid, missing, or X/Z {field} flag at step={index}')
                flags.append(int(row[field]))
            record[count_key] = sum(flags)
            record[f'first_{field}_step'] = next((i for i, v in enumerate(flags) if v), None)
        with np.load(RESULTS_DIR / 'reference' / f'fixed_{algorithm}.npz') as expected:
            es, ec = expected['state_post'][:len(rows)], expected['cov_post'][:len(rows)]
        if rows:
            sd, cd = np.abs(state - es), np.abs(cov - ec)
            mismatch = np.any(state != es, axis=1) | np.any(cov != ec, axis=(1, 2))
            record.update(state_bit_exact_rate=float(np.mean(state == es)), cov_bit_exact_rate=float(np.mean(cov == ec)),
                          state_max_abs_code_diff=int(sd.max()), cov_max_abs_code_diff=int(cd.max()),
                          negative_covariance_diagonal_count=int(np.sum(np.diagonal(cov, axis1=1, axis2=2) < 0)),
                          covariance_symmetry_max_lsb=int(np.max(np.abs(cov - cov.swapaxes(1, 2)))))
            if mismatch.any():
                record.update(implementation_status='FAIL', first_failure_step=int(np.flatnonzero(mismatch)[0]), failure_reason='RTL/Python state or covariance mismatch')
        cycle_rows = csv_rows(directory / f'cycle_counts_{algorithm}.csv')
        for index, row in enumerate(cycle_rows):
            if row.get('step') != str(index):
                raise ValueError(f'cycle CSV order mismatch at step={index}')
        if len(cycle_rows) != len(rows):
            raise ValueError(f'cycle CSV missing/extra row at step={min(len(cycle_rows),len(rows))}')
        cycles = []
        for index, row in enumerate(cycle_rows):
            try: cycles.append(int(row['cycles']))
            except (ValueError, KeyError, TypeError) as error:
                raise ValueError(f'invalid cycle value at step={index}') from error
        if cycles:
            if min(cycles) <= 0:
                raise ValueError('nonpositive update latency')
            record.update(cycles_per_update_min=min(cycles), cycles_per_update_max=max(cycles))
        if record['implementation_status'] != 'FAIL':
            if len(rows) == steps:
                record['implementation_status'] = 'PASS'
            else:
                record.update(first_failure_step=len(rows), failure_reason=f'missing output: completed {len(rows)}/{steps} updates')
        record['numerical_status'] = 'FLAGS_OR_NEGATIVE_DIAGONAL' if any(record.get(k) for k in ('overflow_count', 'solver_error_count', 'numeric_error_count', 'negative_covariance_diagonal_count')) else ('NO_RECORDED_FLAGS' if rows else 'NOT_EVALUATED')
    except (OSError, KeyError, ValueError, IndexError) as error:
        record.update(implementation_status='INCOMPLETE' if isinstance(error, OSError) else 'FAIL', failure_reason=str(error))
        if record['first_failure_step'] is None:
            match = re.search(r'step=(\d+)', str(error))
            record['first_failure_step'] = int(match.group(1)) if match else (0 if isinstance(error,OSError) else record['completed_steps'])
    return record


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--steps', type=int, default=500)
    args = parser.parse_args()
    records = [compare_one(name, steps=args.steps) for name in FILES]
    write_json(RESULTS_DIR / 'rtl_comparison.json', {r['algorithm']: r for r in records})
    keys = list(dict.fromkeys(k for r in records for k in r))
    with (RESULTS_DIR / 'rtl_comparison.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=keys)
        writer.writeheader(); writer.writerows(records)
    for r in records:
        print(f"{r['implementation_status']}: {r['algorithm']} {r['completed_steps']}/{args.steps} updates; numerical={r['numerical_status']} {r['failure_reason']}")
    if any(r['implementation_status'] != 'PASS' for r in records):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
