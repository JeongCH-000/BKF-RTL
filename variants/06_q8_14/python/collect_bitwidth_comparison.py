#!/usr/bin/env python3
"""Copy explicitly labeled comparison evidence; never feed it into new vectors."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import numpy as np
from common import ROOT, RESULTS_DIR, file_checksum, array_checksum, write_json
from compare_nominal_rtl import FILES, csv_rows, load_csv


def snapshot(project: Path, destination: Path, label: str, width: int, frac: int, baseline: bool):
    source_results=project/'results'
    destination.mkdir(parents=True,exist_ok=True)
    shutil.copytree(source_results/'reference',destination/'reference',dirs_exist_ok=True)
    for algorithm,filename in FILES.items():
        for name in (filename,f'cycle_counts_{algorithm}.csv'):
            shutil.copy2(source_results/name,destination/name)
    shutil.copy2(project/'config/nominal.yaml',destination/'nominal.yaml')
    evidence=source_results/'bitwidth'
    for name in ('tool_versions.json','format.json','input_checksums.json','experiment_source_checksums.json','test_status.json','implementation.json'):
        if (evidence/name).exists():shutil.copy2(evidence/name,destination/name)
    if (evidence/'logs').is_dir():shutil.copytree(evidence/'logs',destination/'logs',dirs_exist_ok=True)
    if baseline:
        # Original baseline runner logs live directly in bitwidth; its current
        # EKF TB has no exported flags. Preserve this fact rather than invent 0s.
        for path in evidence.glob('*.log'):shutil.copy2(path,destination/path.name)
        tests=json.loads((evidence/'test_status.json').read_text())
        records=[]
        for algorithm,filename in FILES.items():
            state,cov=load_csv(source_results/filename)
            expected=np.load(source_results/'reference'/f'fixed_{algorithm}.npz')
            rows=csv_rows(source_results/filename)
            test_name=f"{'bkf' if algorithm=='bkf_l1' else algorithm}_500"
            test=next(r for r in tests if r['test']==test_name)
            exact=len(rows)==500 and [int(r['step']) for r in rows]==list(range(500)) and np.array_equal(state,expected['state_post']) and np.array_equal(cov,expected['cov_post'])
            records.append(dict(algorithm=algorithm,requested_steps=500,completed_steps=len(rows),implementation_status='PASS' if exact and test['returncode']==0 else 'FAIL',
                                flag_columns=[name for name in ('overflow','numeric_error','solver_error') if name in rows[0]],
                                first_failure_step=None if exact else next((i for i in range(min(len(rows),500)) if not np.array_equal(state[i],expected['state_post'][i]) or not np.array_equal(cov[i],expected['cov_post'][i])),min(len(rows),500))))
        write_json(destination/'implementation.json',records)
        write_json(destination/'format.json',dict(q_format='signed Q8.16',signed_width=24,fractional_bits=16,provenance='fresh unmodified latest-source isolated run'))
    stimulus=np.load(destination/'reference/stimulus.npz')
    write_json(destination/'input_checksums.json',dict(combined=array_checksum((k,stimulus[k]) for k in sorted(stimulus.files)),
               arrays={k:array_checksum([(k,stimulus[k])]) for k in sorted(stimulus.files)},config_sha256=file_checksum(project/'config/nominal.yaml')))
    write_json(destination/'dataset.json',dict(label=label,W=width,F=frac,origin=str(project),
        role='baseline_q8_16 fresh latest-source run' if baseline else 'peer format actual execution snapshot',
        vector_generation_use='NEVER: comparison evidence only'))
    hashes={str(p.relative_to(destination)):file_checksum(p) for p in sorted(destination.rglob('*')) if p.is_file() and p.name!='snapshot_manifest.json'}
    write_json(destination/'snapshot_manifest.json',hashes)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',required=True,type=Path)
    parser.add_argument('--peer',required=True,type=Path)
    args=parser.parse_args()
    import yaml
    fmt=yaml.safe_load((args.peer/'config/nominal.yaml').read_text())['fixed_point']
    snapshot(args.baseline.resolve(),RESULTS_DIR/'bitwidth/baseline_q8_16','Q8.16',24,16,True)
    snapshot(args.peer.resolve(),RESULTS_DIR/f"bitwidth/peer_q8_{fmt['fractional_bits']}",f"Q8.{fmt['fractional_bits']}",fmt['signed_width'],fmt['fractional_bits'],False)
    print('PASS: baseline and peer comparison evidence copied; active vectors untouched')


if __name__=='__main__':main()
