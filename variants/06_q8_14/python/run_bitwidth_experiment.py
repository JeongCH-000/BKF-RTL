#!/usr/bin/env python3
"""Independent, failure-recording fixed-width regression. Does not invoke Vivado."""
from __future__ import annotations
import csv
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from common import ROOT, RESULTS_DIR, array_checksum, file_checksum, write_json

OUT = RESULTS_DIR / 'bitwidth'


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    logs = OUT / 'logs'; logs.mkdir(exist_ok=True)
    records = []
    def run(name, command, required=True):
        path = logs / f'{name}.log'; start = time.monotonic()
        with path.open('w') as stream:
            stream.write('command: ' + json.dumps(command) + '\n'); stream.flush()
            try:
                result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                        timeout=600, env=dict(os.environ, PYTHON_BIN=sys.executable, MPLBACKEND='Agg'))
                rc = result.returncode
            except subprocess.TimeoutExpired:
                rc = 124; stream.write('\nTIMEOUT after 600 seconds\n')
            except OSError as error:
                rc = 127; stream.write(str(error) + '\n')
        rec = dict(test=name, command=command, returncode=rc,
                   status='PASS' if rc == 0 else ('INCOMPLETE' if rc in (124, 127) else 'FAIL'),
                   seconds=round(time.monotonic()-start, 3), log=str(path.relative_to(ROOT)), required=required)
        records.append(rec); write_json(OUT/'test_status.json', records)
        print(f"{rec['status']}: {name} ({rec['seconds']} s)", flush=True)
        return rc == 0

    python = sys.executable
    generated = run('format_generate', [python, 'python/nominal_config.py', '--generate'])
    for name in ('nominal_models', 'generate_luts', 'generate_nominal_vectors', 'generate_unit_vectors'):
        generated = run(name, [python, f'python/{name}.py']) and generated
    run('reference_tests', [python, 'python/test_reference_models.py'])
    run('lint', [python, 'python/lint_rtl.py'])
    run('pipeline_structure', [python, 'python/check_wns_structure.py'])
    run('unit_tests', ['bash', 'scripts/run_unit_tests.sh'])
    run('independent_arithmetic', [python, 'python/test_bitwidth_arithmetic.py'])
    run('validation_failure_checks', [python, 'python/test_bitwidth_validation.py'])
    if generated:
        from compare_nominal_rtl import FILES, compare_one
        import numpy as np
        comparisons = []
        for algorithm, filename in FILES.items():
            for steps in (1, 500):
                name = f'{algorithm}_{steps}'
                archive = OUT / 'runs' / name; archive.mkdir(parents=True, exist_ok=True)
                for item in (filename, f'cycle_counts_{algorithm}.csv'):
                    (RESULTS_DIR/item).unlink(missing_ok=True)
                    (archive/item).unlink(missing_ok=True)
                cli_algorithm = 'bkf' if algorithm == 'bkf_l1' else algorithm
                ok = run(name, ['bash', 'scripts/run_algorithm_test.sh', cli_algorithm, str(steps)])
                for item in (filename, f'cycle_counts_{algorithm}.csv'):
                    if (RESULTS_DIR/item).is_file(): shutil.copy2(RESULTS_DIR/item, archive/item)
                rec = compare_one(algorithm, archive, steps)
                if not ok:
                    rec['implementation_status'] = 'FAIL' if records[-1]['status'] == 'FAIL' else 'INCOMPLETE'
                    log = (logs/f'{name}.log').read_text()
                    match = re.search(r'(?:step[= ]+)(\d+)', '\n'.join(line for line in log.splitlines() if 'FAIL' in line or 'FATAL' in line or 'mismatch' in line))
                    if match: rec['first_failure_step'] = int(match.group(1))
                    rec['failure_reason'] = '\n'.join(log.splitlines()[-8:])
                write_json(archive/'comparison.json', rec); comparisons.append(rec)
        write_json(OUT/'implementation.json', comparisons)
        for comparison in comparisons:
            if comparison['implementation_status'] != 'PASS':
                test_name = f"{comparison['algorithm']}_{comparison['requested_steps']}"
                for test in records:
                    if test['test'] == test_name and test['status'] == 'PASS':
                        test.update(status=comparison['implementation_status'], returncode=1)
        write_json(OUT/'test_status.json', records)
        run('compare_nominal_rtl', [python, 'python/compare_nominal_rtl.py'])
        run('plots', [python, 'python/plot_nominal_results.py'], required=False)
        stimulus = np.load(RESULTS_DIR/'reference/stimulus.npz')
        checksums = dict(combined=array_checksum((k, stimulus[k]) for k in sorted(stimulus.files)),
                         arrays={k: dict(sha256=array_checksum([(k,stimulus[k])]), shape=list(stimulus[k].shape), dtype=str(stimulus[k].dtype)) for k in sorted(stimulus.files)},
                         config_sha256=file_checksum(ROOT/'config/nominal.yaml'))
        write_json(OUT/'input_checksums.json', checksums)
        for filename in ('rtl_comparison.csv','rtl_comparison.json','lut_error.json','simulation_metrics.csv'):
            if (RESULTS_DIR/filename).exists(): shutil.copy2(RESULTS_DIR/filename,OUT/filename)
    else:
        write_json(OUT/'implementation.json', [dict(algorithm=a,implementation_status='INCOMPLETE', completed_steps=0, failure_reason='vector generation failed') for a in ('ekf','bkf_l1','rbkf_l1','rbkf_l8')])
    if (RESULTS_DIR/'unit').is_dir():
        shutil.copytree(RESULTS_DIR/'unit', OUT/'unit', dirs_exist_ok=True, ignore=shutil.ignore_patterns('*.vvp'))
    versions = dict(python=sys.version, python_executable=sys.executable, vivado='NOT_RUN',
                    iverilog=subprocess.run(['iverilog','-V'],capture_output=True,text=True).stdout.splitlines()[0])
    versions['packages'] = subprocess.run([python,'-m','pip','freeze'],capture_output=True,text=True).stdout.splitlines()
    write_json(OUT/'tool_versions.json',versions)
    source_dirs = ('rtl','python','config','tb','scripts','constraints')
    hashes={str(p.relative_to(ROOT)):file_checksum(p) for d in source_dirs for p in sorted((ROOT/d).rglob('*')) if p.is_file() and '__pycache__' not in p.parts and p.suffix not in ('.vvp','.pyc')}
    write_json(OUT/'experiment_source_checksums.json',hashes)
    run('local_report', [python,'python/report_bitwidth.py'])
    # Refresh the report once so its table includes the report command itself.
    subprocess.run([python,'python/report_bitwidth.py'], cwd=ROOT, check=True)
    if any(r['status'] != 'PASS' for r in records if r['required']):
        raise SystemExit(1)


if __name__ == '__main__': main()
