# Bit-width Comparison

이 문서는 최종 Q8.16 pipeline인 [`05_ekf_overflow_pipeline`](variants/05_ekf_overflow_pipeline/)을 기준으로 [`06_q8_14`](variants/06_q8_14/)와 [`07_q8_12`](variants/07_q8_12/)의 수치 오차, RTL latency와 저장된 FPGA 결과를 비교함. Q8.16의 파이프라이닝 단계별 비교는 [PIPELINING_COMPARISON.md](PIPELINING_COMPARISON.md)에 있음.

## 비교 조건과 변경 범위

- Algorithm regression: seed `20260820`, 500 steps, `Q=1e-3 I`, `R=1e-1 I`
- Configuration: EKF / BKF L=1 / rBKF L=1 / rBKF L=8
- signed Q8.16 / Q8.14 / Q8.12: 부호를 포함한 정수부 8-bit, 전체 storage 24 / 22 / 20-bit
- 반올림·포화: nearest ties away from zero 후 해당 signed width로 saturation
- 기존 알고리즘, LUT 격자·접근 latency, pipeline 단계와 연산 순서는 유지하고 상수·LUT·vector를 형식마다 다시 생성함
- Divider 반복 수 `W+1+F`: 41 / 37 / 33. 비트폭 감소에 따라 계산 cycle이 줄어들며 baseline latency에 맞추는 padding은 없음
- Vivado: `2020.2`, `xc7z020clg400-1`, OOC, 10.000 ns/100 MHz

소프트웨어/RTL 실험은 네 configuration을 모두 포함함. **새 비트폭의 Vivado report는 BKF L=1에만 있음.** 다른 configuration의 자원·timing·power는 측정값이 없으므로 BKF L=1 수치를 대신 사용하지 않음.

## Algorithm verification과 수치 오차

`x_RTL = int_code / 2^F`이며 `MSE = mean((x_RTL - x_target)^2)`, `RMSE = sqrt(MSE)`, `NMSE[dB] = 10 log10(sum(error²)/sum(target²))`임. 500 step과 3개 state의 1,500개 sample에 같은 가중치를 적용함. MSE 변화율은 같은 알고리즘의 Q8.16을 기준으로 계산함.

| Format | Algorithm/model | MSE | RMSE | NMSE (dB) | Q8.16 대비 MSE 변화 | RTL state/cov match |
| --- | --- | --: | --: | --: | --: | --: |
| Q8.16 | EKF fixed/RTL | 0.010064316 | 0.100321 | -38.680059 | 0.0000% | 100% / 100% |
| Q8.14 | EKF fixed/RTL | 0.010065805 | 0.100328 | -38.679417 | +0.0148% | 100% / 100% |
| Q8.12 | EKF fixed/RTL | 0.010103062 | 0.100514 | -38.663372 | +0.3850% | 100% / 100% |
| Q8.16 | BKF L=1 / rBKF L=1 fixed/RTL | 0.015935225 | 0.126235 | -36.684320 | 0.0000% | 100% / 100% |
| Q8.14 | BKF L=1 / rBKF L=1 fixed/RTL | 0.017653236 | 0.132865 | -36.239659 | +10.7812% | 100% / 100% |
| Q8.12 | BKF L=1 / rBKF L=1 fixed/RTL | 0.017352705 | 0.131730 | -36.314230 | +8.8953% | 100% / 100% |
| Q8.16 | rBKF L=8 fixed/RTL | 0.004545607 | 0.067421 | -42.131982 | 0.0000% | 100% / 100% |
| Q8.14 | rBKF L=8 fixed/RTL | 0.004680662 | 0.068415 | -42.004829 | +2.9711% | 100% / 100% |
| Q8.12 | rBKF L=8 fixed/RTL | 0.004658323 | 0.068252 | -42.025605 | +2.4797% | 100% / 100% |

일치율은 **각 형식의 Python integer reference와 RTL 사이**의 비교임. 형식 사이의 추정값은 다름. rBKF L=1은 BKF L=1과 동일한 수치 결과를 내므로 한 행으로 묶음. 단일 seed 결과에서 Q8.12의 BKF 오차가 Q8.14보다 작다고 해서 정밀도를 낮출수록 오차가 줄어든다는 결론을 내릴 수는 없음.

EKF와 BKF/rBKF는 observation resolution이 다름. 같은 알고리즘의 float trajectory와의 차이, state별 RMSE, Python 내부 saturation/floor event와 RTL flag update 수는 [accuracy_comparison.csv](results/bitwidth/accuracy_comparison.csv)에 별도 열로 저장함. 입력과 float 배열의 형식 간 동일성은 [input_float_equivalence.json](results/bitwidth/input_float_equivalence.json)에 기록됨.

| Format | 1/500-step RTL runs | Unit tests | 독립 integer oracle 산술 | CSV 실패 처리 검사 | nominal overflow / numeric / solver updates |
| --- | ---: | ---: | ---: | ---: | --- |
| [Q8.14](results/bitwidth/q8_14/) | 8 / 8 PASS | 9 / 9 PASS | 5175 / 5175 PASS | 10 / 10 PASS | 네 configuration 모두 0 / 0 / 0 |
| [Q8.12](results/bitwidth/q8_12/) | 8 / 8 PASS | 9 / 9 PASS | 5175 / 5175 PASS | 10 / 10 PASS | 네 configuration 모두 0 / 0 / 0 |

두 새 형식은 500/500 step을 모두 완료했고 state/covariance 최대 code difference는 0임. Negative covariance diagonal은 0이며 covariance symmetry 차이는 EKF 0 LSB, BKF/rBKF 최대 1 LSB임. 이 수치 진단과 bit-exact 구현 검증은 별도 지표임.

가져온 Q8.16 비교 snapshot에서 EKF와 rBKF L=1/L=8 CSV에는 오류 flag 열이 없으므로 해당 CSV 집계는 공란임. 원본 testbench의 flag assertion PASS는 [Q8.16 재현 요약](results/bitwidth/q8_16_generalization_summary.json)에 별도 근거로 보존함. 새로운 두 형식의 CSV는 세 flag를 모두 명시적으로 기록함.

## RTL latency와 initiation interval

각 셀은 `latency / initiation interval` cycle임. Latency는 저장된 testbench의 `cycles` 값이며 II는 연속 `start_cycle`의 차이임. 각 configuration에서 500개 output의 latency와 499개 시작 간격을 확인함.

| Variant | EKF | BKF L=1 | rBKF L=1 | rBKF L=8 |
| --- | ---: | ---: | ---: | ---: |
| 05 Q8.16 | 1236 / 1237 | 1306 / 1307 | 1306 / 1307 | 1342 / 1343 |
| 06 Q8.14 | 1200 / 1201 | 1270 / 1271 | 1270 / 1271 | 1306 / 1307 |
| 07 Q8.12 | 1164 / 1165 | 1234 / 1235 | 1234 / 1235 | 1270 / 1271 |

[latency_comparison.csv](results/bitwidth/latency_comparison.csv)는 형식·configuration마다 원본 cycle CSV 경로를 제공함. 이는 Icarus simulation의 cycle 측정값이며 FPGA Fmax나 board throughput 측정값은 아님.

## Vivado post-route comparison

아래 표는 **BKF L=1만 비교**함. Q8.16은 기존 `05` report, Q8.14/Q8.12는 2026-09-11에 저장된 별도 report의 수치임.

| Format / raw reports | LUT | FF | BRAM Tile | DSP | WNS (ns) | WHS (ns) | WPWS (ns) | Power (W) | 100 MHz setup |
| --- | --: | --: | --: | --: | --: | --: | --: | --: | --- |
| [Q8.16](results/vivado/ekf_overflow_pipeline/bkf_l1/) | 5208 | 4725 | 9 | 2 | +0.357 | 0.124 | 4.500 | 0.158 | Pass |
| [Q8.14](results/vivado/q8_14/bkf_l1/) | 4894 | 4371 | 8.5 | 1 | +0.167 | 0.130 | 4.500 | 0.151 | Pass |
| [Q8.12](results/vivado/q8_12/bkf_l1/) | 4447 | 3995 | 7.5 | 1 | +0.284 | 0.096 | 4.500 | 0.146 | Pass |

Q8.16 대비 LUT는 Q8.14에서 6.03%, Q8.12에서 14.61% 감소함. 두 형식 모두 저장된 10 ns setup constraint를 통과하지만 WNS margin은 Q8.16보다 작음. Power는 SAIF/VCD activity file 없이 계산한 vectorless `Total On-Chip Power` estimate이며 confidence는 `Medium`임. 단일 constraint의 WNS나 vectorless power로 Fmax, energy/update 또는 board 소비전력을 추정하지 않음.

OOC report의 범위도 함께 확인해야 함. Q8.14/Q8.12의 `check_timing`에는 input delay 미지정 471/429개와 output delay 미지정 346/316개가 있음. 두 DRC report에는 각각 warning 64개가 기록되어 있으며 RAM async control warning의 report limit 항목도 포함됨. 표의 Pass는 지정된 core timing constraint에 관한 결과임.

각 새 configuration 폴더에는 기존 형식대로 utilization post-synth/post-route, timing, check_timing, DRC, power의 여섯 text report를 보존함. [hardware_comparison.csv](results/bitwidth/hardware_comparison.csv)는 이 report에서 추출한 값과 출처를 제공함.

## 출처와 재현

| 원본 경로 | 저장소 위치 | 범위 |
| --- | --- | --- |
| `Project/BKF_RTL_Q8_14/` | [variants/06_q8_14/](variants/06_q8_14/) | Q8.14 source, config, vectors, 독립 regression |
| `Project/BKF_RTL_Q8_12/` | [variants/07_q8_12/](variants/07_q8_12/) | Q8.12 source, config, vectors, 독립 regression |
| 각 Project의 `results/bitwidth/`, `results/plots/` | [results/bitwidth/](results/bitwidth/) | 가져온 수치·검증 snapshot, cycle CSV, 선택 plot |
| `BKF_Verilog/results_bit-width/results_Q8_14/` | [results/vivado/q8_14/bkf_l1/](results/vivado/q8_14/bkf_l1/) | 2026-09-11 BKF L=1 hardware report |
| `BKF_Verilog/results_bit-width/results_Q8_12/` | [results/vivado/q8_12/bkf_l1/](results/vivado/q8_12/bkf_l1/) | 2026-09-11 BKF L=1 hardware report |

[source_manifest.json](results/bitwidth/source_manifest.json)에 선택한 원본 파일과 공개용 파일의 SHA256 및 경로 변환을 기록함. Host는 `REDACTED`, 사용자 home prefix는 `<USER_HOME>`으로 익명화했으며 측정값은 유지함. 기존 로컬 `results_bit-width/`는 보존하고 DCP, 실행 cache와 복제된 회귀 source tree는 공개용 결과에서 제외함.

원본 software snapshot의 `hardware_status=NOT_RUN`과 `tool_versions.json`의 `vivado=NOT_RUN`은 그 software 실행의 사실을 유지한 기록임. 이후 별도로 저장된 Vivado report와 혼합해 덮어쓰지 않음. 이번 저장소 업데이트에서도 Vivado는 실행하지 않았음.

저장소 이식 후 2026-09-14에 두 variant의 `make all`을 다시 실행해 각각 22/22 stage와 네 configuration의 1/500-step 검증을 통과함. 가져온 원본 기록과 구분한 [package_validation.json](results/bitwidth/package_validation.json)에 새 실행의 결과를 기록함. `06_q8_14`에서 저장소의 `05`를 baseline으로 W24/F16 재현도 다시 실행해 PASS였으며, 104개 reference 배열, 56개 vector 파일과 RTL 8회의 비교 및 baseline source 보존을 확인함. `07_q8_12`에서 같은 재현 target을 별도로 실행하지는 않았음.

루트에서 재현하는 명령은 다음과 같음.

```bash
make setup VARIANT=06_q8_14
make bitwidth VARIANT=06_q8_14
make setup VARIANT=07_q8_12
make bitwidth VARIANT=07_q8_12
make test-q8-16-regression VARIANT=06_q8_14
make vivado VARIANT=06_q8_14 VIVADO_CONFIG=bkf_l1
make vivado VARIANT=07_q8_12 VIVADO_CONFIG=bkf_l1
```

`make bitwidth`의 새 결과는 각 variant의 `results/`에 생성되며 중앙 snapshot을 자동으로 덮어쓰지 않음. `make all`도 같은 비트폭 회귀를 실행함. 과거 24-bit sibling 전용 equivalence 검사는 일반 비트폭 회귀에서 제외하고 현재 W/F의 Python/RTL 비교, 단위·handshake 검사와 별도 W24/F16 재현 검증을 사용함.

원본 Project의 W24/F16 재현은 새로 실행한 최종 Q8.16 원본과 일반화한 경로 사이에서 reference 배열 104개/306,000개 원소, 재생성 vector 56개/30,551개 word와 1/500-step RTL 8회를 비교해 PASS였음. [보존 요약](results/bitwidth/q8_16_generalization_summary.json)은 당시 실행의 compact projection임. 이 검증은 W24/F16 호환성에 대한 것이며 서로 다른 형식의 결과가 bit-exact이거나 새 형식의 모든 Vivado configuration이 검증되었다는 뜻은 아님.
