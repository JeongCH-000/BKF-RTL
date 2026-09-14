# Results

## 조건

- Algorithm regression: seed `20260820`, 500 steps, `Q=1e-3 I`, `R=1e-1 I`
- Fixed point: 기준 `01`–`05`는 signed Q8.16 (24-bit); 비트폭 실험 `06`/`07`은 Q8.14 (22-bit) / Q8.12 (20-bit)
- Vivado: `2020.2`, `xc7z020clg400-1`, OOC, 10.000 ns/100 MHz
- Configuration order: EKF / BKF L=1 / rBKF L=1 / rBKF L=8

파이프라이닝 단계별 알고리즘 오차, latency, 자원, WNS, power의 통합 비교는 [PIPELINING_COMPARISON.md](PIPELINING_COMPARISON.md), 비트폭별 비교는 [BITWIDTH_COMPARISON.md](BITWIDTH_COMPARISON.md)에서 확인 가능함. 이 문서는 상세 검증 근거와 raw report index를 제공함.

## Algorithm verification

아래 표와 단계 간 equivalence 수치는 Q8.16의 `01`–`05`를 대상으로 함.

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

## Bit-width verification

Q8.14/Q8.12는 네 configuration에서 각각 one-step과 500-step 검증을 통과했고, 각 형식의 Python integer reference 대비 state/covariance 최대 code difference는 0임. 아래 수치는 500-step RTL output을 해당 `2^F`로 나누어 실제 target과 비교한 RMSE임.

| Format | EKF RMSE | BKF L=1 RMSE | rBKF L=1 RMSE | rBKF L=8 RMSE |
| --- | --: | --: | --: | --: |
| Q8.16 | 0.100321 | 0.126235 | 0.126235 | 0.067421 |
| Q8.14 | 0.100328 | 0.132865 | 0.132865 | 0.068415 |
| Q8.12 | 0.100514 | 0.131730 | 0.131730 | 0.068252 |

새 두 형식의 nominal overflow/numeric/solver flag update와 negative posterior covariance diagonal은 모두 0임. 이는 해당 seed에서의 수치 진단이며 형식 간 추정값의 동일성을 뜻하지 않음. W24/F16으로 되돌린 일반화 RTL과 기존 Q8.16 구현의 재현 검증, 독립 산술·CSV 실패 검사와 원본 결과는 [비트폭 검증 자료](results/bitwidth/)에 정리함.

2026-09-14 저장소 이식 후 두 variant의 22개 회귀 단계와 구조 검사를 다시 통과했고, `06_q8_14`의 W24/F16 재현도 통과함. 이번 실행의 상세 결과는 [package_validation.json](results/bitwidth/package_validation.json)에 보존함.

## RTL latency와 initiation interval

각 셀은 `latency / initiation interval` cycle임.

| Variant | EKF | BKF L=1 | rBKF L=1 | rBKF L=8 |
| --- | ---: | ---: | ---: | ---: |
| Baseline | 620 / 621 | 654 / 655 | 654 / 655 | 669 / 670 |
| Pipelined | 1169 / 1170 | 1248 / 1249 | 1248 / 1249 | 1281 / 1282 |
| Divider pipeline | 1187 / 1188 | 1266 / 1267 | 1266 / 1267 | 1299 / 1300 |
| WNS closure | 1236 / 1237 | 1306 / 1307 | 1306 / 1307 | 1342 / 1343 |
| EKF overflow pipeline | 1236 / 1237 | 1306 / 1307 | 1306 / 1307 | 1342 / 1343 |
| Q8.14 | 1200 / 1201 | 1270 / 1271 | 1270 / 1271 | 1306 / 1307 |
| Q8.12 | 1164 / 1165 | 1234 / 1235 | 1234 / 1235 | 1270 / 1271 |

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
| Q8.14 | BKF L=1 | 4894 | 4371 | 8.5 | 1 | +0.167 | 0.130 | 4.500 | 0.151 | Pass |
| Q8.12 | BKF L=1 | 4447 | 3995 | 7.5 | 1 | +0.284 | 0.096 | 4.500 | 0.146 | Pass |

Power는 simulation activity file 없이 계산한 vectorless estimate이고 confidence는 모두 `Medium`임. 단일 10 ns run의 WNS로 Fmax, throughput 또는 energy/update를 추정하지 않음.

Q8.14/Q8.12의 hardware 수치는 2026-09-11에 저장된 BKF L=1 report에서 가져옴. 다른 configuration의 비트폭별 Vivado report는 없으며 이번 저장소 업데이트에서도 Vivado를 실행하지 않음. 소프트웨어 실험 당시의 `NOT_RUN` 기록과 이후 hardware report의 출처는 [BITWIDTH_COMPARISON.md](BITWIDTH_COMPARISON.md)에 구분함.

## 저장된 waveform

| File | Configuration | 내용 |
| --- | --- | --- |
| [`ekf_smoke.vcd`](results/waveforms/baseline/ekf_smoke.vcd) | Baseline EKF | 5-step full-resolution EKF smoke waveform |
| [`bkf_smoke.vcd`](results/waveforms/baseline/bkf_smoke.vcd) | Baseline BKF L=1 | 5-step 1-bit BKF smoke waveform |
| [`rbkf_l8_smoke.vcd`](results/waveforms/baseline/rbkf_l8_smoke.vcd) | Baseline rBKF L=8 | 5-step multi-branch rBKF smoke waveform |

동일 폴더의 CSV에는 output 및 cycle count가 저장되어 있음. Git에 포함된 VCD는 baseline에만 있으며, 다른 variant의 smoke waveform은 각 단계의 `make wave`로 다시 생성 가능함.

최종 Q8.16 구현에는 [별도 파형 검증 실행기](validation/final_waveform/README.md)를 추가함. 네 configuration에서 baseline/full/debug 각각 500-step을 실행해 총 12회 / 6,000 update를 확인하며, full은 500-step, debug는 앞 10-step VCD를 기록함. State/covariance와 기존 output/cycle CSV 비교, VCD handshake·payload·clock·latency 검증을 포함함.

| Configuration | TB latency (cycles) | II (cycles) | VCD acceptance → result_valid edge (cycles) |
| --- | ---: | ---: | ---: |
| EKF | 1236 | 1237 | 1235 |
| BKF L=1 | 1306 | 1307 | 1305 |
| rBKF L=1 | 1306 | 1307 | 1305 |
| rBKF L=8 | 1342 | 1343 | 1341 |

TB latency는 acceptance cycle을 포함하므로 edge 간 순수 간격보다 1 cycle 큼. [최종 파형 검증 자료](results/waveforms/final/)에는 CSV·검증 요약을 저장하고, full/debug VCD는 `make wave-final`로 로컬에서 재생성함. 생성 후 `make verify-wave-final`로 다시 검사 가능함.

2026-09-14 저장소 경로에서 12회 / 6,000 update와 8개 VCD를 다시 생성·검증했고, 생성 결과 재검사 및 source 보존 확인도 통과함. 이번 실행은 [repository_validation.json](results/waveforms/final/repository_validation.json), 2026-09-11 원본 실행은 [summary.json](results/waveforms/final/summary.json)에 구분해 보존함.

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
- [Q8.14 BKF L=1](results/vivado/q8_14/bkf_l1/)
- [Q8.12 BKF L=1](results/vivado/q8_12/bkf_l1/)
