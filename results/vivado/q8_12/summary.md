# Q8.12 RTL Vivado results

공통 조건: Vivado `2020.2`, target part `xc7z020clg400-1`, clock period `10.000 ns` (100 MHz), post-route임. Power는 vectorless `Total On-Chip Power` 추정값이며 report confidence는 `Medium`임.

| Algorithm | LUT | FF | BRAM Tile | DSP | WNS (ns) | WHS (ns) | WPWS (ns) | Power (W) |
| --- | --: | --: | --: | --: | --: | --: | --: | --: |
| BKF L=1 | 4447 | 3995 | 7.5 | 1 | 0.284 | 0.096 | 4.500 | 0.146 |

2026-09-11에 저장된 `results_bit-width/results_Q8_12/`의 여섯 text report를 [bkf_l1/](bkf_l1/)에 정리함. Report design은 `bkf_l1_core`이며 EKF/rBKF 결과는 포함하지 않음. 이번 저장소 업데이트에서 Vivado를 다시 실행하지 않았음.

Host·user-home prefix를 익명화하고 줄 끝 공백을 정리함. 수치와 report 날짜는 유지하며, 원본/공개용 SHA256은 [source_manifest.json](../../bitwidth/source_manifest.json)에 기록함. DCP는 제외함.

OOC core의 지정된 setup constraint를 통과했으며, `check_timing`의 미지정 I/O delay와 DRC warning은 raw report에 보존함. 전체 수치/latency 비교와 해석은 [BITWIDTH_COMPARISON.md](../../../BITWIDTH_COMPARISON.md)에 있음.
