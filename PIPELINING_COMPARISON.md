# Pipelining Stage Comparison

이 문서는 다섯 구현 단계와 네 configuration의 알고리즘 오차, latency, FPGA 자원, timing, power를 한 표에서 비교함.

## 비교 조건과 해석

- Configuration: EKF / BKF L=1 / rBKF L=1 / rBKF L=8
- Algorithm regression: seed `20260820`, 500 steps, `Q=1e-3 I`, `R=1e-1 I`
- Fixed point: signed Q8.16, 24-bit storage
- Vivado: `2020.2`, `xc7z020clg400-1`, out-of-context implementation, 10.000 ns/100 MHz
- `MSE = mean((x_RTL - x_target)^2) = RMSE^2`: 500 step과 3개 state 전체 1,500개 sample의 평균임. 표의 MSE는 full-precision RMSE에서 계산한 뒤 반올림함.
- `Latency / II`: Icarus에서 측정한 cycle 수이며, `II`는 initiation interval임.
- `Power`: simulation activity file 없이 계산한 Vivado vectorless estimate이며 confidence는 모두 `Medium`임.

파이프라이닝은 register 위치와 연산 schedule만 변경하며 알고리즘은 변경하지 않음. 다섯 variant의 500-step fixed-point 결과와 RTL 결과가 모두 bit-exact이므로 **MSE, RMSE, NMSE는 단계별로 동일**함. 반면 latency, 자원, WNS, power는 implementation 단계에 따라 달라짐.

EKF와 BKF/rBKF는 observation resolution이 다르므로 MSE/RMSE를 동일 입력 해상도에서의 직접적인 우열로 해석하면 안 됨. rBKF L=1은 BKF L=1 equivalence configuration임.

## 단계별 통합 결과

표의 configuration 링크는 해당 단계의 raw Vivado report 폴더로 연결됨. 수치는 표시 자릿수에 맞춰 반올림함.

| Stage | Configuration / raw reports | MSE (RMSE²) | RMSE | NMSE (dB) | Latency / II (cycle) | LUT | FF | BRAM / DSP | WNS (ns) | Power (W) | 100 MHz setup |
| --- | --- | --: | --: | --: | ---: | --: | --: | ---: | --: | --: | --- |
| [01 Baseline](variants/01_baseline/) | [EKF](results/vivado/baseline/ekf_l1/) | 0.010064316 | 0.100321 | -38.680059 | 620 / 621 | 4507 | 3885 | 9 / 2 | -15.808 | 0.190 | Fail |
| [01 Baseline](variants/01_baseline/) | [BKF L=1](results/vivado/baseline/bkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 654 / 655 | 4244 | 3745 | 9 / 2 | -15.217 | 0.188 | Fail |
| [01 Baseline](variants/01_baseline/) | [rBKF L=1](results/vivado/baseline/rbkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 654 / 655 | 4244 | 3745 | 9 / 2 | -15.217 | 0.188 | Fail |
| [01 Baseline](variants/01_baseline/) | [rBKF L=8](results/vivado/baseline/rbkf_l8/) | 0.004545607 | 0.067421 | -42.131982 | 669 / 670 | 4407 | 3792 | 9 / 2 | -15.142 | 0.187 | Fail |
| [02 Pipelined](variants/02_pipelined/) | [EKF](results/vivado/pipelined/ekf_l1/) | 0.010064316 | 0.100321 | -38.680059 | 1169 / 1170 | 4503 | 4131 | 9 / 2 | -3.439 | 0.153 | Fail |
| [02 Pipelined](variants/02_pipelined/) | [BKF L=1](results/vivado/pipelined/bkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 1248 / 1249 | 4357 | 4004 | 9 / 2 | -3.212 | 0.150 | Fail |
| [02 Pipelined](variants/02_pipelined/) | [rBKF L=1](results/vivado/pipelined/rbkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 1248 / 1249 | 4357 | 4004 | 9 / 2 | -3.212 | 0.150 | Fail |
| [02 Pipelined](variants/02_pipelined/) | [rBKF L=8](results/vivado/pipelined/rbkf_l8/) | 0.004545607 | 0.067421 | -42.131982 | 1281 / 1282 | 4466 | 4036 | 9 / 2 | -3.419 | 0.151 | Fail |
| [03 Divider pipeline](variants/03_divider_pipeline/) | [EKF](results/vivado/divider_pipeline/ekf_l1/) | 0.010064316 | 0.100321 | -38.680059 | 1187 / 1188 | 4248 | 4305 | 9 / 2 | -1.360 | 0.147 | Fail |
| [03 Divider pipeline](variants/03_divider_pipeline/) | [BKF L=1](results/vivado/divider_pipeline/bkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 1266 / 1267 | 4283 | 4170 | 9 / 2 | -0.631 | 0.152 | Fail |
| [03 Divider pipeline](variants/03_divider_pipeline/) | [rBKF L=1](results/vivado/divider_pipeline/rbkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 1266 / 1267 | 4283 | 4170 | 9 / 2 | -0.631 | 0.152 | Fail |
| [03 Divider pipeline](variants/03_divider_pipeline/) | [rBKF L=8](results/vivado/divider_pipeline/rbkf_l8/) | 0.004545607 | 0.067421 | -42.131982 | 1299 / 1300 | 4347 | 4197 | 9 / 2 | -0.781 | 0.150 | Fail |
| [04 WNS closure](variants/04_wns_closure/) | [EKF](results/vivado/wns_closure/ekf_l1/) | 0.010064316 | 0.100321 | -38.680059 | 1236 / 1237 | 5329 | 4861 | 9 / 2 | -0.401 | 0.164 | Fail |
| [04 WNS closure](variants/04_wns_closure/) | [BKF L=1](results/vivado/wns_closure/bkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 1306 / 1307 | 5184 | 4720 | 9 / 2 | +0.095 | 0.156 | Pass |
| [04 WNS closure](variants/04_wns_closure/) | [rBKF L=1](results/vivado/wns_closure/rbkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 1306 / 1307 | 5184 | 4720 | 9 / 2 | +0.095 | 0.156 | Pass |
| [04 WNS closure](variants/04_wns_closure/) | [rBKF L=8](results/vivado/wns_closure/rbkf_l8/) | 0.004545607 | 0.067421 | -42.131982 | 1342 / 1343 | 5319 | 4750 | 9 / 2 | +0.115 | 0.159 | Pass |
| [05 EKF overflow pipeline](variants/05_ekf_overflow_pipeline/) | [EKF](results/vivado/ekf_overflow_pipeline/ekf_l1/) | 0.010064316 | 0.100321 | -38.680059 | 1236 / 1237 | 5349 | 4860 | 9 / 2 | +0.097 | 0.166 | Pass |
| [05 EKF overflow pipeline](variants/05_ekf_overflow_pipeline/) | [BKF L=1](results/vivado/ekf_overflow_pipeline/bkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 1306 / 1307 | 5208 | 4725 | 9 / 2 | +0.357 | 0.158 | Pass |
| [05 EKF overflow pipeline](variants/05_ekf_overflow_pipeline/) | [rBKF L=1](results/vivado/ekf_overflow_pipeline/rbkf_l1/) | 0.015935225 | 0.126235 | -36.684320 | 1306 / 1307 | 5208 | 4725 | 9 / 2 | +0.357 | 0.158 | Pass |
| [05 EKF overflow pipeline](variants/05_ekf_overflow_pipeline/) | [rBKF L=8](results/vivado/ekf_overflow_pipeline/rbkf_l8/) | 0.004545607 | 0.067421 | -42.131982 | 1342 / 1343 | 5343 | 4749 | 9 / 2 | +0.218 | 0.158 | Pass |

## 단계별 핵심 변경

| Stage | 핵심 변경 | 100 MHz setup 통과 |
| --- | --- | ---: |
| 01 Baseline | Shared serial arithmetic/divider | 0 / 4 |
| 02 Pipelined | Operand → product → arithmetic → commit pipeline | 0 / 4 |
| 03 Divider pipeline | Register-separated restoring divider | 0 / 4 |
| 04 WNS closure | Determinant finalize와 covariance writeback pipeline | 3 / 4 |
| 05 EKF overflow pipeline | EKF overflow predicate/sticky-status register separation | 4 / 4 |

## 요약

- 알고리즘 정확도는 전 단계에서 동일함. 파이프라이닝으로 인한 state/covariance code mismatch는 0임.
- Baseline에서 최종 단계까지 WNS는 EKF `-15.808 → +0.097 ns`, BKF/rBKF L=1 `-15.217 → +0.357 ns`, rBKF L=8 `-15.142 → +0.218 ns`로 개선됨.
- 같은 구간에서 vectorless power estimate는 EKF `0.190 → 0.166 W`, BKF/rBKF L=1 `0.188 → 0.158 W`, rBKF L=8 `0.187 → 0.158 W`로 감소함.
- timing closure를 위해 latency와 register/LUT 사용량은 증가함. 이 구조는 독립 update를 겹치지 않는 single-issue 구조이므로 latency/II만으로 Fmax, throughput, energy/update를 추정하지 않음.

더 상세한 알고리즘 검증, per-axis RMSE, WHS/WPWS, waveform 및 report 설명은 [RESULTS.md](RESULTS.md)에서 확인 가능함.
