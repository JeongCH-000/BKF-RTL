#!/usr/bin/env python3
"""Validate final RTL captures using shared variant sources and compact evidence."""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import numpy as np

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]
SOURCE = REPO / 'variants/05_ekf_overflow_pipeline'
EVIDENCE = REPO / 'results/waveforms/final'
ROOT = HERE / '.work'
FIXED = {}
sys.path.insert(0, str(SOURCE / 'python'))
DESIGNS = {
    'ekf_l1': ('ekf', 'tb_ekf_full', 'tb_ekf_full.dut.u_engine', 1, 1236),
    'bkf_l1': ('bkf_l1', 'tb_bkf_full', 'tb_bkf_full.dut', 1, 1306),
    'rbkf_l1': ('rbkf_l1', 'tb_rbkf_full', 'tb_rbkf_full.dut.u_engine', 1, 1306),
    'rbkf_l8': ('rbkf_l8', 'tb_rbkf_full', 'tb_rbkf_full.dut.u_engine', 8, 1342),
}
COMMON_SOURCES = [
    'rtl/common/fx_divider_q8_16.v',
    'rtl/common/fx_determinant_finalize_pipeline.v',
    'rtl/common/fx_mul_mac_pipeline.v',
    'rtl/nonlinear/q8_16_rsqrt_lut.v',
    'rtl/nonlinear/arcsine_cov_lut_q8_16.v',
    'rtl/bkf/bkf_core.v',
]
MODES = ('baseline', 'full', 'debug')
RESULTS = ROOT / 'results/validation'
LOGS = ROOT / 'results/logs'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def run(command, log):
    print('+ ' + ' '.join(map(str, command)), flush=True)
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
    output = log.read_text()
    if result.returncode:
        print(output, flush=True)
        raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
    for line in output.splitlines():
        if line.startswith(('PASS:', 'VCD info:')):
            print(line, flush=True)
    require('FAIL:' not in output and 'ERROR:' not in output, f'Failure in {log}')
    return output


def audit():
    manifest = json.loads((EVIDENCE / 'source_manifest.json').read_text())
    for relative, record in manifest['files'].items():
        require(sha(SOURCE / relative) == record['sha256'],
                f'Final RTL/TB/vector differs from archived waveform input: {relative}')
    observer_sha256 = sha(HERE / 'tb/waveform/waveform_capture.sv')
    require(observer_sha256 == manifest['observer_sha256'], 'Original read-only waveform observer changed')
    current = dict(manifest['files'])
    for directory, pattern in [('python', '*.py'), ('config', '*')]:
        for path in sorted((SOURCE / directory).glob(pattern)):
            if path.is_file():
                current[str(path.relative_to(SOURCE))] = {'sha256': sha(path)}
    current['scripts/run_algorithm_test.sh'] = {
        'sha256': sha(SOURCE / 'scripts/run_algorithm_test.sh')}
    return {'archived_input_files_checked': len(manifest['files']),
            'observer_sha256': observer_sha256,
            'current_model_and_inputs_sha256': hashlib.sha256(
                json.dumps(current, sort_keys=True).encode()).hexdigest()}


def prepare_workspace():
    ROOT.mkdir(parents=True, exist_ok=True)
    for name in ('rtl', 'tb', 'vectors'):
        target = ROOT / name
        if target.is_symlink():
            require(target.resolve() == (SOURCE / name).resolve(), f'Unexpected link: {target}')
        else:
            require(not target.exists(), f'Expected a source symlink: {target}')
            target.symlink_to(os.path.relpath(SOURCE / name, ROOT), target_is_directory=True)
    (ROOT / 'scripts').mkdir(exist_ok=True)
    # This unchanged script derives its output directory from its own location.
    shutil.copy2(SOURCE / 'scripts/run_algorithm_test.sh', ROOT / 'scripts/run_algorithm_test.sh')
    for directory in ('results/rtl', 'results/waveform'):
        (ROOT / directory).mkdir(parents=True, exist_ok=True)


def result_files(algorithm):
    return [f'rtl_{algorithm}_outputs.csv', f'cycle_counts_{algorithm}.csv']


def simulate(design, debug_steps):
    algorithm, top, core, branches, _ = DESIGNS[design]
    selected = 'bkf' if algorithm == 'bkf_l1' else algorithm
    for mode in MODES:
        (RESULTS / mode).mkdir(parents=True, exist_ok=True)
    output = run(['bash', 'scripts/run_algorithm_test.sh', selected, '500'], LOGS / f'{design}_baseline.log')
    require('PASS: 500/500' in output, f'{design}: missing baseline PASS')
    for filename in result_files(algorithm):
        shutil.copy2(ROOT / 'results' / filename, RESULTS / 'baseline' / filename)
    sources = COMMON_SOURCES.copy()
    if algorithm == 'ekf':
        sources.append('rtl/ekf/ekf_core.v')
    elif algorithm.startswith('rbkf'):
        sources.append('rtl/rbkf/rbkf_core.v')
    sources += [f'tb/integration/{top}.sv', str(HERE / 'tb/waveform/waveform_capture.sv')]
    executable = f'results/rtl/{design}_waveform.vvp'
    command = ['iverilog', '-g2012', '-gstrict-expr-width', '-Wall',
               '-Wno-sensitivity-entire-array', '-Wimplicit', '-DWAVE_DEBUG',
               '-DWNS_CLOSURE_ASSERTIONS', '-I.', f'-DWV_TB={top}', f'-DWV_CORE={core}',
               f'-Pwaveform_capture.NUM_BRANCHES={branches}']
    if algorithm.startswith('rbkf'):
        command.append(f'-P{top}.NUM_BRANCHES={branches}')
    command += ['-s', top, '-s', 'waveform_capture', '-o', executable] + sources
    run(command, LOGS / f'{design}_compile.log')
    for mode in ('full', 'debug'):
        path = wave_path(design, mode)
        path.parent.mkdir(parents=True, exist_ok=True)
        command = ['vvp', executable, '+STEPS=500', f'+CAPTURE_FILE={path.relative_to(ROOT)}']
        if mode == 'debug':
            command.append(f'+CAPTURE_DEBUG_STEPS={debug_steps}')
        output = run(command, LOGS / f'{design}_{mode}.log')
        require('PASS: 500/500' in output, f'{design}: missing {mode} PASS')
        for filename in result_files(algorithm):
            shutil.copy2(ROOT / 'results' / filename, RESULTS / mode / filename)
        if mode == 'debug':
            trim_debug_tail(path)


def wave_path(design, mode):
    return ROOT / 'waveforms' / mode / (design + ('_debug' if mode == 'debug' else '') + '.vcd')


def trim_debug_tail(path):
    """Remove timestamps after $dumpoff ends, including the empty 500-step end time.

    Retains every recorded value and the final standard VCD $dumpoff block.
    This makes GTKWave's zoom-to-fit show the recorded ten-step interval.
    """
    temporary = path.with_suffix('.vcd.tmp')
    found = False
    with path.open() as source, temporary.open('w') as target:
        for line in source:
            target.write(line)
            if line.strip() == '$dumpoff':
                found = True
            elif found and line.strip() == '$end':
                break
    require(found, f'Missing debug cutoff in {path}')
    temporary.replace(path)


def read_csv(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def compare_csvs(design):
    algorithm, _, _, _, latency = DESIGNS[design]
    expected_state = FIXED[algorithm]['state_post']
    expected_cov = FIXED[algorithm]['cov_post']
    for filename in result_files(algorithm):
        original = read_csv(EVIDENCE / 'outputs' / filename)
        require(len(original) == 500, f'Original {filename}: missing rows')
        for mode in MODES:
            rows = read_csv(RESULTS / mode / filename)
            require(rows == original, f'{design}/{mode}: CSV differs from final project: {filename}')
    for mode in MODES:
        rows = read_csv(RESULTS / mode / f'rtl_{algorithm}_outputs.csv')
        state = np.array([[int(row[f'state_{i}_int']) for i in range(3)] for row in rows])
        cov = np.array([[[int(row[f'cov_{i}{j}_int']) for j in range(3)] for i in range(3)] for row in rows])
        require(np.array_equal(state, expected_state), f'{design}/{mode}: Python state mismatch')
        require(np.array_equal(cov, expected_cov), f'{design}/{mode}: Python covariance mismatch')
        require([int(r['step']) for r in rows] == list(range(500)), 'Missing or reordered steps')
        cycles = read_csv(RESULTS / mode / f'cycle_counts_{algorithm}.csv')
        require(all(int(row['cycles']) == latency for row in cycles), f'{design}: latency changed')
        require(all(int(cycles[i]['start_cycle']) - int(cycles[i-1]['start_cycle']) == latency + 1
                    for i in range(1, 500)), f'{design}: initiation interval changed')
    return {'simulation': 'PASS', 'python_match': 'PASS', 'state_mismatches': 0,
            'covariance_mismatches': 0, 'final_output_csv_match': 'PASS',
            'final_cycle_csv_match': 'PASS', 'testbench_latency_cycles': latency,
            'initiation_interval_cycles': latency + 1, 'steps_per_run': 500,
            'simulation_modes': list(MODES)}


def check_arrays(name, actual):
    expected = json.loads((EVIDENCE / 'reference_manifest.json').read_text())['archives'][name]
    require(set(actual) == set(expected), f'{name}: reference fields changed')
    for field, value in actual.items():
        array = np.asarray(value)
        array = np.ascontiguousarray(array.astype(array.dtype.newbyteorder('<'), copy=False))
        record = expected[field]
        require(list(array.shape) == record['shape'] and array.dtype.str == record['dtype']
                and hashlib.sha256(array.tobytes(order='C')).hexdigest() == record['sha256'],
                f'{name}: recomputed reference differs at {field}')


def recheck_fixed_model(design):
    from nominal_models import generate_nominal_sequence, run_fixed_filter
    algorithm, _, _, branches, _ = DESIGNS[design]
    kind = 'ekf' if algorithm == 'ekf' else ('bkf' if algorithm == 'bkf_l1' else 'rbkf')
    stimulus = generate_nominal_sequence()
    check_arrays('stimulus', stimulus)
    actual = run_fixed_filter(kind, stimulus, branches)
    check_arrays(f'fixed_{algorithm}', actual.values)
    FIXED[algorithm] = actual.values
    return {'status': 'PASS', 'fields_compared': len(actual.values),
            'stimulus': 'reconstructed from variant nominal configuration',
            'reference_files_overwritten': False}


def verify_evidence(design):
    algorithm, _, _, _, latency = DESIGNS[design]
    rows = read_csv(EVIDENCE / 'outputs' / f'rtl_{algorithm}_outputs.csv')
    require(len(rows) == 500 and [int(row['step']) for row in rows] == list(range(500)),
            f'{design}: expected 500 ordered archived outputs')
    state = np.array([[int(row[f'state_{i}_int']) for i in range(3)] for row in rows])
    cov = np.array([[[int(row[f'cov_{i}{j}_int']) for j in range(3)] for i in range(3)] for row in rows])
    require(np.array_equal(state, FIXED[algorithm]['state_post']), f'{design}: archived state mismatch')
    require(np.array_equal(cov, FIXED[algorithm]['cov_post']), f'{design}: archived covariance mismatch')
    cycles = read_csv(EVIDENCE / 'outputs' / f'cycle_counts_{algorithm}.csv')
    require([int(row['step']) for row in cycles] == list(range(500)),
            f'{design}: expected 500 ordered archived cycle rows')
    require(len(cycles) == 500 and all(int(row['cycles']) == latency for row in cycles),
            f'{design}: archived latency mismatch')
    require(all(int(row['result_cycle']) - int(row['start_cycle']) == int(row['cycles'])
                for row in cycles), f'{design}: archived result/start cycle mismatch')
    require(all(int(cycles[i]['start_cycle']) - int(cycles[i-1]['start_cycle']) == latency + 1
                for i in range(1, 500)), f'{design}: archived initiation interval mismatch')


def inspect_vcd(design, mode, debug_steps):
    path = wave_path(design, mode)
    algorithm, _, core, _, latency = DESIGNS[design]
    expected_count = 500 if mode == 'full' else debug_steps
    state_expected = [int(s, 16) for s in (ROOT / 'vectors/nominal' / algorithm / 'expected_state.mem').read_text().split()]
    cov_expected = [int(s, 16) for s in (ROOT / 'vectors/nominal' / algorithm / 'expected_cov.mem').read_text().split()]
    signals, scope, values = {}, [], {}
    timestamp, last_timestamp = 0, -1
    pending = {}
    result_times, accept_times, completion_times, rising_times = [], [], [], []
    widths = {}
    names = ['clk', 'rst_n', 'input_valid', 'input_ready', 'result_valid', 'result_ready',
             'done', 'state_out_flat', 'cov_out_flat', 'overflow_flag', 'numeric_error', 'solver_error']
    ids = {}

    def bit(name, mapping):
        return mapping.get(ids[name], 'x')

    def frame():
        previous = values.copy()
        values.update(pending)
        if bit('clk', previous) == '0' and bit('clk', values) == '1':
            rising_times.append(timestamp)
            if bit('rst_n', previous) == '1':
                if bit('input_valid', previous) == '1' and bit('input_ready', previous) == '1':
                    accept_times.append(timestamp)
                if bit('result_valid', previous) == '1' and bit('result_ready', previous) == '1':
                    completion_times.append(timestamp)
        if bit('rst_n', values) == '1' and bit('result_valid', previous) != '1' and bit('result_valid', values) == '1':
            index = len(result_times)
            require(index < expected_count, f'{path}: extra result pulse')
            for name, expected in [('state_out_flat', state_expected), ('cov_out_flat', cov_expected)]:
                code = bit(name, values)
                require('x' not in code and 'z' not in code and int(code, 2) == expected[index],
                        f'{path}: VCD {name} mismatch step {index}')
            require(all(bit(n, values) == '0' for n in ['overflow_flag', 'numeric_error', 'solver_error']),
                    f'{path}: error flag at valid output')
            require(bit('done', values) == '1', f'{path}: done/result alignment')
            result_times.append(timestamp)
        pending.clear()

    timescale = None
    with path.open() as stream:
        for raw in stream:
            line = raw.strip()
            if line.startswith('$timescale'):
                require(timescale is None, f'{path}: duplicate VCD timescale')
                declaration = line.removeprefix('$timescale').split()
                while '$end' not in declaration:
                    continuation = next(stream, None)
                    require(continuation is not None, f'{path}: unterminated VCD timescale')
                    declaration.extend(continuation.split())
                timescale = ''.join(declaration[:declaration.index('$end')])
                require(timescale == '1ps', f'{path}: expected VCD timescale 1ps, got {timescale!r}')
            elif line.startswith('$scope'):
                scope.append(line.split()[2])
            elif line.startswith('$upscope'):
                scope.pop()
            elif line.startswith('$var'):
                fields = line.split()
                name = '.'.join(scope + [fields[4]])
                signals[name] = fields[3]
                widths[name] = int(fields[2])
            elif line.startswith('$enddefinitions'):
                break
        require(timescale == '1ps', f'{path}: missing VCD timescale 1ps')
        required = ['clk', 'rst_n', 'cfg_valid', 'cfg_ready', 'cfg_state_flat', 'cfg_cov_flat',
                    'input_valid', 'input_ready', 'f_input_flat', 'measurement_flat',
                    'observation_valid', 'branch_observation_bits', 'threshold_valid',
                    'threshold_flat', 'result_valid', 'result_ready', 'done', 'fsm_state',
                    'state_out_flat', 'cov_out_flat', 'overflow_flag', 'numeric_error', 'solver_error']
        for name in required:
            require('waveform_capture.' + name in signals, f'{path}: missing {name}')
        for name in names:
            ids[name] = signals['waveform_capture.' + name]
        if mode == 'debug':
            for name in ['state', 'mul_request_valid', 'mul_request_ready', 'pipe_result_valid',
                         'pipeline_stage1_valid', 'pipeline_stage2_valid', 'pipeline_stage3_valid',
                         'divider_start', 'divider_busy', 'divider_valid', 'divider_quotient',
                         'branch_reduction_valid', 'branch_observation_hold', 'branch_index',
                         'pipe_mac_sum', 'det_capture_stage_valid', 'det_round_stage_valid',
                         'det_floor_stage_valid', 'cov_predict_overflow_local_valid_reg']:
                require(core + '.' + name in signals, f'{path}: missing internal {name}')
            for name in ['waveform_capture.vector_element[0].state_predict',
                         'waveform_capture.vector_element[0].branch_sum',
                         'waveform_capture.matrix_element[0].cov_predict',
                         'waveform_capture.matrix_element[8].gain']:
                require(name in signals, f'{path}: missing array exposure {name}')
        wanted = set(ids.values())
        for raw in stream:
            line = raw.strip()
            if not line:
                continue
            if line.startswith('#'):
                frame()
                new_time = int(line[1:])
                require(new_time >= timestamp, f'{path}: timestamps out of order')
                timestamp = new_time
                last_timestamp = timestamp
            elif line[0] in '01xz':
                if line[1:] in wanted:
                    pending[line[1:]] = line[0]
            elif line[0] in 'bB':
                data, identifier = line.split()
                if identifier in wanted:
                    pending[identifier] = data[1:].lower()
        frame()
    require(len(result_times) == len(accept_times) == len(completion_times) == expected_count,
            f'{path}: pulse counts result/input/completed={len(result_times)}/{len(accept_times)}/{len(completion_times)} expected={expected_count}')
    require(all(b-a == 10000 for a,b in zip(rising_times, rising_times[1:])), f'{path}: clock period changed')
    # Original TB counts the acceptance cycle inclusively. Edge-to-edge is one less.
    require(all(r-a == (latency-1)*10000 for a,r in zip(accept_times,result_times)), f'{path}: edge latency changed')
    return {'path': str(path.relative_to(ROOT)), 'bytes': path.stat().st_size,
            'sha256': sha(path), 'declared_signals': len(signals), 'result_pulses': len(result_times),
            'input_handshakes': len(accept_times), 'output_handshakes': len(completion_times),
            'vcd_state_covariance_match': 'PASS', 'timescale': timescale, 'clock_period_ns': 10,
            'acceptance_to_result_valid_edge_cycles': latency - 1,
            'first_result_ps': result_times[0], 'last_result_ps': result_times[-1],
            'recording_end_ps': last_timestamp}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('design', choices=['all', *DESIGNS], nargs='?', default='all')
    parser.add_argument('--debug-steps', type=int, default=10)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--verify-only', action='store_true', help='Recheck locally generated VCD/CSV/logs')
    mode.add_argument('--evidence-only', action='store_true', help='Check tracked evidence and recompute Python references without simulation')
    args = parser.parse_args()
    require(5 <= args.debug_steps <= 20, 'debug-steps must be in 5..20')
    before = audit()
    if not args.evidence_only:
        if args.verify_only:
            require(RESULTS.is_dir(), 'No local waveform results; run make wave_all first')
        else:
            prepare_workspace()
        os.chdir(ROOT)
        LOGS.mkdir(parents=True, exist_ok=True)
        RESULTS.mkdir(parents=True, exist_ok=True)
    selected = list(DESIGNS) if args.design == 'all' else [args.design]
    summary = {'generated_at': time.strftime('%Y-%m-%dT%H:%M:%S%z'), 'project': str(HERE.relative_to(REPO)),
               'source_variant': str(SOURCE.relative_to(REPO)),
               'python': sys.version.split()[0], 'numpy': np.__version__, 'debug_steps': args.debug_steps,
               'audit_before': before, 'designs': {}}
    for design in selected:
        print(f'\n=== {design} ===', flush=True)
        reference = recheck_fixed_model(design)
        verify_evidence(design)
        if args.evidence_only:
            print(f'PASS: {design}: archived state/cov/cycles, stimulus and 13 fixed trace fields', flush=True)
            continue
        if not args.verify_only:
            simulate(design, args.debug_steps)
        record = compare_csvs(design)
        record['fixed_model_recomputed'] = reference
        record['waveforms'] = {mode: inspect_vcd(design, mode, args.debug_steps) for mode in ('full', 'debug')}
        for mode in MODES:
            require('PASS: 500/500' in (LOGS / f'{design}_{mode}.log').read_text(), f'{design}/{mode}: missing PASS log')
        summary['designs'][design] = record
        write_json(RESULTS / f'{design}_summary.json', record)
        print(f'PASS: {design}: 3 x 500-step simulation, Python state/cov, original outputs/cycles, full/debug VCD', flush=True)
    summary['audit_after'] = audit()
    require(summary['audit_after'] == before, 'Shared source files changed during validation')
    if args.evidence_only:
        print('PASS: tracked evidence verified; shared source inputs unchanged')
        return
    write_json(RESULTS / ('summary.json' if args.design == 'all' else f'{args.design}_run.json'), summary)
    print(f'\nGenerated workspace: {ROOT}')
    for design, record in summary['designs'].items():
        print(f'{design}: Simulation PASS | Python reference PASS | Final cycle/output match PASS')
        for wave in record['waveforms'].values():
            print(f"  {wave['path']} ({wave['bytes']:,} bytes)")
    print(f'Documentation: {HERE / "README.md"}')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
