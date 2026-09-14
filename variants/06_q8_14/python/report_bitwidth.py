#!/usr/bin/env python3
"""Metrics from actual saved arrays and RTL CSVs; unrun hardware fields stay empty."""
from __future__ import annotations
import csv
import json
from pathlib import Path
import numpy as np
from common import ROOT, RESULTS_DIR, array_checksum, write_json
from fixed_math import WIDTH, FRAC
from compare_nominal_rtl import FILES, load_csv, csv_rows

OUT = RESULTS_DIR/'bitwidth'


def read_json(path, default=None):
    return json.loads(path.read_text()) if path.exists() else default


def metrics(state, target, float_state):
    error = state-target
    mse=float(np.mean(error**2))
    return dict(MSE=mse, RMSE=float(np.sqrt(mse)), NMSE_dB=float(10*np.log10(np.sum(error**2)/np.sum(target**2))),
                RMSE_x=float(np.sqrt(np.mean(error[:,0]**2))), RMSE_y=float(np.sqrt(np.mean(error[:,1]**2))), RMSE_z=float(np.sqrt(np.mean(error[:,2]**2))),
                difference_from_float_MSE=float(np.mean((state-float_state)**2)),
                difference_from_float_RMSE=float(np.sqrt(np.mean((state-float_state)**2))))


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    datasets=[dict(label=f'Q8.{FRAC}', W=WIDTH,F=FRAC,results=RESULTS_DIR, evidence=OUT,origin=str(ROOT))]
    for path in sorted(OUT.glob('baseline_q8_16'))+sorted(OUT.glob('peer_q8_*')):
        info=read_json(path/'dataset.json')
        if info: datasets.append(dict(info,results=path,evidence=path))
    datasets.sort(key=lambda d:-d['F'])
    rows=[]; equality=[]
    baseline=next((d for d in datasets if d['F']==16),None)
    for ds in datasets:
        ref=ds['results']/'reference'
        if not (ref/'stimulus.npz').exists(): continue
        stimulus=np.load(ref/'stimulus.npz'); target=stimulus['target']
        checksum=array_checksum((k,stimulus[k]) for k in sorted(stimulus.files))
        tests=read_json(ds['evidence']/'implementation.json',[])
        stats=read_json(ref/'summary.json',{}).get('algorithms',{})
        for algorithm,filename in FILES.items():
            fl=np.load(ref/f'float_{algorithm}.npz')['state_post']
            fp=np.load(ref/f'fixed_{algorithm}.npz')['state_post']/float(1<<ds['F'])
            base_mse=None
            if baseline:
                base_ref=baseline['results']/'reference'
                base_target=np.load(base_ref/'stimulus.npz')['target']
                base_state=np.load(base_ref/f'fixed_{algorithm}.npz')['state_post']/65536.0
                base_mse=float(np.mean((base_state-base_target)**2))
                base_stim=np.load(base_ref/'stimulus.npz')
                base_float=np.load(base_ref/f'float_{algorithm}.npz')
                own_float=np.load(ref/f'float_{algorithm}.npz')
                equality.append(dict(format=ds['label'],algorithm=algorithm,
                    raw_arrays_equal=all(k in base_stim and np.array_equal(stimulus[k],base_stim[k]) for k in stimulus.files),
                    float_arrays_equal=all(k in base_float and np.array_equal(own_float[k],base_float[k]) for k in own_float.files)))
            models=[('Python fixed',fp)]
            if ds is (baseline or datasets[0]): models.insert(0,('float reference',fl))
            rtl_path=ds['results']/filename
            rtl_status='INCOMPLETE'; completed=0; flags={}; cycle_min=cycle_max=None
            archived=next((r for r in tests if r.get('algorithm')==algorithm and r.get('requested_steps')==500),{})
            if rtl_path.exists():
                try:
                    rtl_state,rtl_cov=load_csv(rtl_path); raw=csv_rows(rtl_path);completed=len(raw)
                    expected=np.load(ref/f'fixed_{algorithm}.npz')
                    if len(raw)==500 and [int(r['step']) for r in raw]==list(range(500)) and np.array_equal(rtl_state,expected['state_post']) and np.array_equal(rtl_cov,expected['cov_post']):
                        rtl_status='PASS' if archived.get('implementation_status')=='PASS' else archived.get('implementation_status','UNVERIFIED_TEST_STATUS')
                    elif len(raw)==500: rtl_status='FAIL'
                    for name in ('overflow','numeric_error','solver_error'):
                        if raw and name in raw[0]:
                            flags[f'RTL_{name}_updates']=sum(int(r[name]) for r in raw)
                        elif ds['F'] != 16:
                            raise ValueError(f'new-format CSV missing required {name} flag')
                    flags['negative_covariance_diagonal_count']=int(np.sum(np.diagonal(rtl_cov,axis1=1,axis2=2)<0))
                    cycle_values=[int(r['cycles']) for r in csv_rows(ds['results']/f'cycle_counts_{algorithm}.csv')]
                    if len(cycle_values)==500:cycle_min,cycle_max=min(cycle_values),max(cycle_values)
                    models.append(('RTL output',rtl_state/(1<<ds['F']) if completed==500 else None))
                except (ValueError,KeyError,OSError):
                    rtl_status='FAIL'; models.append(('RTL output',None))
            else: models.append(('RTL output',None))
            for source,state in models:
                row=dict(algorithm=algorithm,Q_format='float64' if source=='float reference' else ds['label'],
                         W='' if source=='float reference' else ds['W'],F='' if source=='float reference' else ds['F'],
                         metric_source=source,source_project=ds['origin'],input_checksum=checksum,
                         requested_steps=500,completed_steps=completed if source=='RTL output' else 500,
                         RTL_verification_status=rtl_status if source=='RTL output' else '',
                         MSE=None,RMSE=None,NMSE_dB=None,RMSE_x=None,RMSE_y=None,RMSE_z=None,
                         MSE_change_vs_Q8_16_percent=None,difference_from_float_MSE=None,difference_from_float_RMSE=None,
                         Python_internal_saturation_events=None,Python_determinant_floor_events=None,Python_diagonal_floor_events=None,
                         RTL_overflow_updates=None,RTL_numeric_error_updates=None,RTL_solver_error_updates=None,
                         negative_covariance_diagonal_count=None,cycles_per_update_min=None,cycles_per_update_max=None,
                         RTL_flag_source=('actual CSV flags' if all(k in flags for k in ('RTL_overflow_updates','RTL_solver_error_updates','RTL_numeric_error_updates')) else 'not exported by baseline EKF CSV; no invented counts') if source=='RTL output' else '',
                         LUT=None,FF=None,DSP=None,BRAM=None,WNS_ns=None,estimated_power_W=None,hardware_status='NOT_RUN')
                if state is not None and np.isfinite(state).all():
                    row.update(metrics(state,target,fl))
                    if base_mse and source!='float reference':row['MSE_change_vs_Q8_16_percent']=(row['MSE']/base_mse-1)*100
                if source=='Python fixed':
                    arithmetic=stats.get(algorithm,{}).get('fixed_arithmetic',{})
                    row.update(Python_internal_saturation_events=arithmetic.get('saturation_count'),Python_determinant_floor_events=arithmetic.get('determinant_floor_count'),Python_diagonal_floor_events=arithmetic.get('diagonal_floor_count'))
                    covariance=np.load(ref/f'fixed_{algorithm}.npz')['cov_post']
                    row['negative_covariance_diagonal_count']=int(np.sum(np.diagonal(covariance,axis1=1,axis2=2)<0))
                if source=='RTL output':row.update(flags,cycles_per_update_min=cycle_min,cycles_per_update_max=cycle_max)
                rows.append(row)
    write_json(OUT/'accuracy_comparison.json',rows)
    write_json(OUT/'input_float_equivalence.json',equality)
    if rows:
        with (OUT/'accuracy_comparison.csv').open('w',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    status=read_json(OUT/'test_status.json',[])
    def fmt(v):return '' if v is None or v=='' else (f'{v:.8g}' if isinstance(v,float) else str(v))
    lines=[f'# Signed Q8.{FRAC} bit-width experiment', '',
        f'Current project: `{ROOT}`. Active W={WIDTH}, F={FRAC}; sign is included in the 8 integer bits.', '',
        'Scope: seed 20260820, 500 updates, all three state components and every step equally weighted. One seed only; errors need not change monotonically with precision.', '',
        'MSE = mean((int_code / 2^F - target)^2); RMSE = sqrt(MSE); NMSE[dB] = 10 log10(sum(error^2) / sum(target^2)). State RMSE and the difference from the same algorithm’s floating trajectory are separate CSV columns. MSE change uses fresh baseline_q8_16 Python fixed output; its RTL agreement is checked separately.', '',
        'The baseline EKF CSV did not export flags; its count fields stay blank. Its original testbench independently rejected any asserted error flag. New-format CSVs explicitly export all three flags. Python internal saturation events count individual arithmetic operations. RTL error counts count updates whose actual CSV flag equals 1. Solver floor events and negative covariance diagonals are reported as numerical behavior independently of bit-exact implementation status.', '',
        '## Executed tests','', '| Test | Status | Seconds |','|---|---|---:|']
    lines += [f"| {r['test']} | {r['status']} | {r['seconds']} |" for r in status]
    lines += ['', '## Accuracy and RTL comparison','', '| Algorithm | Format | Source | RTL | MSE | RMSE | NMSE dB | MSE change % | Cycles | Overflow / solver updates |', '|---|---|---|---|---:|---:|---:|---:|---:|---|']
    for row in rows:
        lines.append('| '+' | '.join(fmt(row[k]) for k in ('algorithm','Q_format','metric_source','RTL_verification_status','MSE','RMSE','NMSE_dB','MSE_change_vs_Q8_16_percent','cycles_per_update_min'))+f" | {fmt(row['RTL_overflow_updates'])} / {fmt(row['RTL_solver_error_updates'])} |")
    lines += ['', '## Hardware results', '', '| Format | LUT | FF | DSP | BRAM | WNS | Estimated power | Status |','|---|---:|---:|---:|---:|---:|---:|---|']
    lines += [f"| {d['label']} | | | | | | | NOT_RUN |" for d in datasets]
    lines += ['', 'Vivado was not executed. The unchanged constraint is 10.000 ns (100 MHz); the unchanged default part is xc7z020clg400-1. No area, power, or timing improvement is inferred.', '',
        'Reproduce current format: `make bitwidth` (or `make all`). Run hardware flow separately: `make vivado`; select a configuration with `VIVADO_CONFIG=ekf_l1 make vivado` (also bkf_l1, rbkf_l1, rbkf_l8).', '',
        'Baseline and peer directories in results/bitwidth are explicitly labeled comparison snapshots, never consumed by vector generation or current-format RTL tests. The nominal run regenerates deterministic floating stimulus arrays from the unchanged generator and seed; raw BKF_python data are not required by this curated variant. No old CSV/NPZ/HEX is used as new-format output.', '',
        'The independent target uses current-format Python/RTL comparison and directed unit/handshake/pipeline tests. Run `make test-q8-16-regression` separately for generalized W24/F16 versus a fresh isolated copy of ../05_ekf_overflow_pipeline. See q8_16_regression_reproduction/summary.json after execution.', '']
    if equality:lines += ['Input and floating-array invariance: '+('PASS' if all(r['raw_arrays_equal'] and r['float_arrays_equal'] for r in equality) else 'FAIL')+'.','']
    (OUT/'SUMMARY.md').write_text('\n'.join(lines))
    print(f"PASS: wrote {len(rows)} accuracy rows with explicit metric provenance and empty hardware fields")
    if equality and not all(r['raw_arrays_equal'] and r['float_arrays_equal'] for r in equality):raise SystemExit(1)


if __name__=='__main__':main()
