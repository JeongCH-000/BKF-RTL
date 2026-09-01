# Results

## 조건

- Algorithm regression: seed `20260820`, 500 steps, `Q=1e-3 I`, `R=1e-1 I`
- Fixed point: signed Q8.16, 24-bit storage
- Vivado: `2020.2`, `xc7z020clg400-1`, OOC, 10.000 ns/100 MHz
- Configuration order: EKF / BKF L=1 / rBKF L=1 / rBKF L=8

파이프라이닝 단계별 알고리즘 오차, latency, 자원, WNS, power의 통합 비교는 [PIPELINING_COMPARISON.md](PIPELINING_COMPARISON.md)에서 확인 가능함. 이 문서는 상세 검증 근거와 raw report index를 제공함.

## Algorithm verification

| Algorithm/model | RMSE | RMSE x1 | RMSE x2 | RMSE x3 | NMSE (dB) | RTL state/cov match |
| --- | --: | --: | --: | --: | --: | --: |
| EKF fixed/RTL | 0.100321 | 0.081191 | 0.118053 | 0.098308 | -38.680059 | 100% / 100% |
| BKF L=1 fixed/RTL | 0.126235 | 0.101993 | 0.149030 | 0.123260 | -36.684320 | 100% / 100% |
| rBKF L=8 fixed/RTL | 0.067421 | 0.053602 | 0.079302 | 0.066894 | -42.131982 | 100% / 100% |

rBKF L=1은 BKF L=1 equivalence configuration이므로 별도 성능 행에서 제외함. 두 configuration의 float/fixed trace와 RTL 결과는 동일함.

검증 결과:

- 모든 variant에서 네 configuration의 one-step 및 500-step regression PASS
- Python integer reference 대비 state/covariance 최대 code difference 0
- nominal overflow 0, solver error 0, negative covariance diagonal 0
- EKF covariance symmetry 0 LSB, BKF/rBKF 최대 1 LSB
- WNS-closure 전후 2,000 output transaction과 transaction당 19개 intermediate field mismatch 0
- EKF-overflow pipeline 전후 2,000 output/status transaction과 19개 intermediate/status field mismatch 0
- EKF overflow/round/saturation/sticky-status 전후 directed·randomized 2,073 paired transaction semantic mismatch 0

단계 간 equivalence는 각각 `make test VARIANT=04_wns_closure`와 `make test VARIANT=05_ekf_overflow_pipeline`의 기본 regression에 포함됨. 두 경우 모두 직전 variant와 현재 variant를 동일 testbench/vector로 별도 compile한 후 CSV를 비교함.

## RTL latency와 initiation interval

각 셀은 `latency / initiation interval` cycle임.

| Variant | EKF | BKF L=1 | rBKF L=1 | rBKF L=8 |
| --- | ---: | ---: | ---: | ---: |
| Baseline | 620 / 621 | 654 / 655 | 654 / 655 | 669 / 670 |
| Pipelined | 1169 / 1170 | 1248 / 1249 | 1248 / 1249 | 1281 / 1282 |
| Divider pipeline | 1187 / 1188 | 1266 / 1267 | 1266 / 1267 | 1299 / 1300 |
| WNS closure | 1236 / 1237 | 1306 / 1307 | 1306 / 1307 | 1342 / 1343 |
| EKF overflow pipeline | 1236 / 1237 | 1306 / 1307 | 1306 / 1307 | 1342 / 1343 |

이 값은 Icarus cycle measurement이며 FPGA clock frequency 또는 throughput 측정값이 아님.

## Vivado post-route comparison

| Variant | Configuration | LUT | FF | BRAM | DSP | WNS (ns) | WHS (ns) | WPWS (ns) | Power (W) | 100 MHz |
| --- | --- | --: | --: | --: | --: | --: | --: | --: | --: | --- |
| Baseline | EKF | 4507 | 3885 | 9 | 2 | -15.808 | 0.156 | 4.500 | 0.190 | Fail |
| Baseline | BKF L=1 | 4244 | 3745 | 9 | 2 | -15.217 | 0.155 | 4.500 | 0.188 | Fail |
| Baseline | rBKF L=1 | 4244 | 3745 | 9 | 2 | -15.217 | 0.155 | 4.500 | 0.188 | Fail |
| Baseline | rBKF L=8 | 4407 | 3792 | 9 | 2 | -15.142 | 0.136 | 4.500 | 0.187 | Fail |
| Pipelined | EKF | 4503 | 4131 | 9 | 2 | -3.439 | 0.110 | 4.500 | 0.153 | Fail |
| Pipelined | BKF L=1 | 4357 | 4004 | 9 | 2 | -3.212 | 0.155 | 4.500 | 0.150 | Fail |
| Pipelined | rBKF L=1 | 4357 | 4004 | 9 | 2 | -3.212 | 0.155 | 4.500 | 0.150 | Fail |
| Pipelined | rBKF L=8 | 4466 | 4036 | 9 | 2 | -3.419 | 0.153 | 4.500 | 0.151 | Fail |
| Divider pipeline | EKF | 4248 | 4305 | 9 | 2 | -1.360 | 0.122 | 4.500 | 0.147 | Fail |
| Divider pipeline | BKF L=1 | 4283 | 4170 | 9 | 2 | -0.631 | 0.143 | 4.500 | 0.152 | Fail |
| Divider pipeline | rBKF L=1 | 4283 | 4170 | 9 | 2 | -0.631 | 0.143 | 4.500 | 0.152 | Fail |
| Divider pipeline | rBKF L=8 | 4347 | 4197 | 9 | 2 | -0.781 | 0.149 | 4.500 | 0.150 | Fail |
| WNS closure | EKF | 5329 | 4861 | 9 | 2 | -0.401 | 0.098 | 4.500 | 0.164 | Fail |
| WNS closure | BKF L=1 | 5184 | 4720 | 9 | 2 | +0.095 | 0.096 | 4.500 | 0.156 | Pass |
| WNS closure | rBKF L=1 | 5184 | 4720 | 9 | 2 | +0.095 | 0.096 | 4.500 | 0.156 | Pass |
| WNS closure | rBKF L=8 | 5319 | 4750 | 9 | 2 | +0.115 | 0.110 | 4.500 | 0.159 | Pass |
| EKF overflow pipeline | EKF | 5349 | 4860 | 9 | 2 | +0.097 | 0.124 | 4.500 | 0.166 | Pass |
| EKF overflow pipeline | BKF L=1 | 5208 | 4725 | 9 | 2 | +0.357 | 0.124 | 4.500 | 0.158 | Pass |
| EKF overflow pipeline | rBKF L=1 | 5208 | 4725 | 9 | 2 | +0.357 | 0.124 | 4.500 | 0.158 | Pass |
| EKF overflow pipeline | rBKF L=8 | 5343 | 4749 | 9 | 2 | +0.218 | 0.125 | 4.500 | 0.158 | Pass |

Power는 simulation activity file 없이 계산한 vectorless estimate이고 confidence는 모두 `Medium`임. 단일 10 ns run의 WNS로 Fmax, throughput 또는 energy/update를 추정하지 않음.

## 저장된 waveform

| File | Configuration | 내용 |
| --- | --- | --- |
| [`ekf_smoke.vcd`](results/waveforms/baseline/ekf_smoke.vcd) | Baseline EKF | 5-step full-resolution EKF smoke waveform |
| [`bkf_smoke.vcd`](results/waveforms/baseline/bkf_smoke.vcd) | Baseline BKF L=1 | 5-step 1-bit BKF smoke waveform |
| [`rbkf_l8_smoke.vcd`](results/waveforms/baseline/rbkf_l8_smoke.vcd) | Baseline rBKF L=8 | 5-step multi-branch rBKF smoke waveform |

동일 폴더의 CSV에는 output 및 cycle count가 저장되어 있음. 현재 VCD는 baseline에만 있으며, 다른 variant는 각 단계의 `make wave`로 다시 생성 가능함.

## Raw Vivado reports

각 configuration에는 다음 여섯 report가 있음.

- `utilization_post_synth.rpt`
- `utilization_post_route.rpt`
- `timing_post_route.rpt`
- `check_timing_post_route.rpt`
- `drc_post_route.rpt`
- `power_post_route.rpt`

Raw report:

- [Baseline](results/vivado/baseline/)
- [Pipelined](results/vivado/pipelined/)
- [Divider pipeline](results/vivado/divider_pipeline/)
- [WNS closure](results/vivado/wns_closure/)
- [EKF overflow pipeline](results/vivado/ekf_overflow_pipeline/)
