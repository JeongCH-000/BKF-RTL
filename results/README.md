# Result artifacts

전체 결과 해석과 단계별 비교는 [`RESULTS.md`](../RESULTS.md)에 있음.

## 포함된 파일

- `plots/`: 최종 algorithm comparison plot 3개
- `waveforms/baseline/`: baseline 5-step VCD 3개와 대응 CSV
- `vivado/`: 5 variants × 4 configurations × 6 text reports
- `vivado/<variant>/summary.md`: 해당 variant의 간단한 결과표

Vivado configuration 이름은 Tcl과 동일하게 `ekf_l1`, `bkf_l1`, `rbkf_l1`, `rbkf_l8`로 통일함.

## 공개 저장소 정리

Raw Vivado report의 Windows host name과 user-home prefix는 익명화했으며 측정 수치는 유지함. 다음 생성물은 크기와 재현성 때문에 제외함.

- `post_route.dcp`
- Vivado project cache/run directory
- Icarus `*.vvp`
- 회귀 중간 CSV, debug trace, source snapshot
- 중복 plot과 Python binary dataset

새 실행에서 생성되는 variant-local `results/`는 `.gitignore` 대상임. 저장된 evidence는 이 중앙 `results/`만 추적함.
