# Result artifacts

전체 결과 해석과 단계별 비교는 [`RESULTS.md`](../RESULTS.md)에 있음.

## 포함된 파일

- `plots/`: 최종 algorithm comparison plot 3개
- `waveforms/baseline/`: baseline 5-step VCD 3개와 대응 CSV
- `waveforms/final/`: 최종 Q8.16의 네 configuration × baseline/full/debug 500-step 파형 검증 요약과 CSV
- `bitwidth/`: Q8.14/Q8.12 수치·구현 검증, Q8.16 재현 비교와 출처 기록
- `vivado/`: 기존 Q8.16 5 variants × 4 configurations × 6 text reports와 Q8.14/Q8.12 BKF L=1의 각 6개 report
- `vivado/<variant>/summary.md`: 해당 variant의 간단한 결과표

Vivado configuration 이름은 Tcl과 동일하게 `ekf_l1`, `bkf_l1`, `rbkf_l1`, `rbkf_l8`로 통일함.

비트폭 결과 해석과 hardware 측정 범위는 [`BITWIDTH_COMPARISON.md`](../BITWIDTH_COMPARISON.md)에 있음. 최종 파형은 [`validation/final_waveform/`](../validation/final_waveform/)에서 재생성하며, 원본 실행 기록과 저장소에서 다시 실행한 결과를 구분함.

## 공개 저장소 정리

Raw Vivado report의 Windows host name과 user-home prefix는 익명화했으며 측정 수치는 유지함. 다음 생성물은 크기와 재현성 때문에 제외함.

- `post_route.dcp`
- Vivado project cache/run directory
- Icarus `*.vvp`
- 회귀 중간 CSV, debug trace, source snapshot
- 중복 plot과 Python binary dataset
- 최종 500-step full/debug VCD (실행기로 재생성)

새 실행에서 생성되는 variant-local `results/`와 파형 검증 작업 디렉터리는 `.gitignore` 대상임. 저장된 evidence는 이 중앙 `results/`만 추적함. 기존 로컬 `results_bit-width/`는 보존하되 Git에서 제외하고, 공개용 text report를 `vivado/q8_14/`와 `vivado/q8_12/`에 정리함.
