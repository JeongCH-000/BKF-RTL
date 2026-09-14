# Final waveform evidence

`Project/final_waveform_validation`의 500-step 검증 결과를 보존한 compact evidence다.
실행 방법과 신호 설명은 [`validation/final_waveform/README.md`](../../../validation/final_waveform/README.md)에 있다.

| 파일 | 내용 |
| --- | --- |
| `summary.json` | 2026-09-11 원본 실행 summary; 네 설계 × 세 모드, VCD의 크기/hash/handshake/latency |
| `repository_validation.json` | 2026-09-14 공개 저장소 전체 재실행 및 저장된 VCD 재검증 결과 |
| `outputs/rtl_*_outputs.csv` | 원본 500-step state/covariance 결과 |
| `outputs/cycle_counts_*.csv` | 원본 latency와 acceptance/result cycle |
| `rtl_comparison.csv`, `rtl_comparison.json` | 원본 Python–RTL bit-exact 비교 및 covariance 통계 |
| `reference_summary.json` | 원본 float/fixed RMSE, NMSE와 arithmetic 통계 |
| `reference_manifest.json` | 원본 stimulus 및 fixed NPZ의 배열별 shape/dtype/SHA-256 |
| `source_manifest.json` | 재사용하는 원본 RTL/LUT/integration TB/`.mem`의 SHA-256 |

원본 summary의 개인 절대경로는 `Project/final_waveform_validation`으로 정리했으며 수치는 유지했다.
원본 파일 감사의 `154`/`408` counts는 당시 복사본/원본 프로젝트에 대한 기록이다.
현재 공개 저장소의 파일 수나 새 검증 결과를 나타내지 않는다.
원본 VCD 경로와 hash는 당시 파일을 설명하며 해당 대용량 파일은 Git에서 제외했다.

`repository_validation.json`에는 이 저장소에서 다시 실행한 12회의 500-step simulation,
VCD 재검증, 71개 원본 input 및 read-only observer hash 검사 결과를 별도로 보존했다.

재현 시 생성되는 VCD, 로그 및 모드별 CSV/JSON은
`validation/final_waveform/.work/`에 저장된다. 중앙 evidence는 자동으로 덮어쓰지 않는다.
새 checkout에서도 `make -C validation/final_waveform verify-evidence`로 저장된 CSV와
현재 Python 모델이 동일한 stimulus 및 13개 fixed trace field를 재현하는지 검사할 수 있다.
