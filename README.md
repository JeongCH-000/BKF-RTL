# BKF_Verilog

Lorenz attractor의 3차원 상태 추정을 위한 EKF, 1-bit Bussgang Kalman Filter(BKF), reduced multi-branch BKF(rBKF)를 signed Q8.16 RTL로 구현하고 Q8.14/Q8.12까지 비트폭을 확장 평가한 프로젝트임. 합성 가능한 Verilog-2001, SystemVerilog testbench, deterministic vector, Python bit-accurate reference, Icarus regression, Vivado 2020.2 post-route 결과를 함께 제공함.

기본 구현은 [`05_ekf_overflow_pipeline`](variants/05_ekf_overflow_pipeline/)임. 추가한 [`06_q8_14`](variants/06_q8_14/)와 [`07_q8_12`](variants/07_q8_12/)는 같은 pipeline의 비트폭 실험이며, 저장된 Vivado 결과는 BKF L=1에 한정됨.

## 구현 범위

- EKF: full-resolution measurement를 사용하는 기준 구현
- BKF L=1: feature마다 1-bit observation 사용
- rBKF L=1: BKF와의 bit-exact equivalence 확인용
- rBKF L=8: 독립 noise를 가진 8개 branch bit를 feature별 평균
- Lorenz parameters: `sigma=10`, `rho=28`, `beta=8/3`, `dt=0.02`
- 실험 조건: seed `20260820`, 500 steps, `Q=1e-3 I`, `R=1e-1 I`

EKF와 BKF/rBKF는 observation resolution이 다르므로 RMSE는 동일 입력 해상도의 직접적인 우열 비교가 아니라 각 구현의 추정 품질 참고값임.

## 고정소수점 datapath

기준 구현 `01`–`05`의 산술 형식은 다음과 같음.

- signed 24-bit Q8.16
- round-to-nearest, exact ties away from zero
- rounding 후 signed 24-bit saturation
- 48-bit multiplier와 최소 50-bit three-term MAC accumulator
- 41-iteration restoring divider
- reciprocal-square-root 및 `(2/pi)asin(x)` LUT
- ready/valid handshake와 output backpressure 지원

Lorenz transition matrix `F_t`는 software에서 계산해 RTL에 입력.

`06`/`07`은 같은 반올림·포화 정책과 pipeline 경계를 유지하며 W/F를 각각 22/14, 20/12로 변경함. 상수·LUT·입력/기대 vector는 해당 형식으로 다시 생성하고 divider 반복 수는 각각 37/33임. 호환성을 위해 유지한 `q8_16` 파일·모듈 이름의 실제 비트폭은 생성된 헤더를 따름.

## 개발 단계

표의 configuration 순서는 EKF / BKF L=1 / rBKF L=1 / rBKF L=8임.

Q8.16의 MSE/RMSE, latency, 자원, WNS, power 단계별 통합 비교는 [PIPELINING_COMPARISON.md](PIPELINING_COMPARISON.md), 비트폭 비교는 [BITWIDTH_COMPARISON.md](BITWIDTH_COMPARISON.md)에서 확인 가능함.

| Variant | 핵심 변경 | Latency (cycles) | Vivado WNS (ns) | 100 MHz setup |
| --- | --- | --- | --- | --- |
| [01 Baseline](variants/01_baseline/) | Shared serial arithmetic/divider | 620 / 654 / 654 / 669 | -15.808 / -15.217 / -15.217 / -15.142 | 모두 Fail |
| [02 Pipelined](variants/02_pipelined/) | Operand → product → arithmetic → commit pipeline | 1169 / 1248 / 1248 / 1281 | -3.439 / -3.212 / -3.212 / -3.419 | 모두 Fail |
| [03 Divider pipeline](variants/03_divider_pipeline/) | Register-separated restoring divider | 1187 / 1266 / 1266 / 1299 | -1.360 / -0.631 / -0.631 / -0.781 | 모두 Fail |
| [04 WNS closure](variants/04_wns_closure/) | Determinant finalize와 covariance writeback pipeline | 1236 / 1306 / 1306 / 1342 | -0.401 / +0.095 / +0.095 / +0.115 | EKF만 Fail |
| [05 EKF overflow pipeline](variants/05_ekf_overflow_pipeline/) | EKF overflow predicate/sticky-status register separation | 1236 / 1306 / 1306 / 1342 | +0.097 / +0.357 / +0.357 / +0.218 | 모두 Pass |

각 variant는 독립 update를 겹쳐 실행하지 않는 single-issue 구조임. Q8.16 최종 구현의 initiation interval은 각각 1237 / 1307 / 1307 / 1343 cycles임.

## 최종 Q8.16 Vivado 결과

공통 조건은 Vivado `2020.2`, `xc7z020clg400-1`, 10.000 ns clock, out-of-context implementation임.

| Configuration | LUT | FF | BRAM Tile | DSP | WNS (ns) | Power (W) |
| --- | --: | --: | --: | --: | --: | --: |
| EKF | 5349 | 4860 | 9 | 2 | +0.097 | 0.166 |
| BKF L=1 | 5208 | 4725 | 9 | 2 | +0.357 | 0.158 |
| rBKF L=1 | 5208 | 4725 | 9 | 2 | +0.357 | 0.158 |
| rBKF L=8 | 5343 | 4749 | 9 | 2 | +0.218 | 0.158 |

Power는 activity file을 사용하지 않은 vectorless estimate이며 Vivado confidence는 `Medium`임. 단계별 통합 비교는 [PIPELINING_COMPARISON.md](PIPELINING_COMPARISON.md), 상세 검증 결과와 원본 report는 [RESULTS.md](RESULTS.md)에 정리함.

## 비트폭 실험

동일 seed·500-step에서 각 형식의 Python integer reference와 RTL state/covariance가 모두 일치함. 비트폭 간 추정값은 달라지며, 아래 RMSE는 실제 target 대비 BKF L=1 결과임.

| Variant | W / F | BKF L=1 RMSE | Latency / II (cycles) | LUT | FF | BRAM / DSP | WNS (ns) | Power (W) |
| --- | ---: | --: | ---: | --: | --: | ---: | --: | --: |
| [05 Q8.16](variants/05_ekf_overflow_pipeline/) | 24 / 16 | 0.126235 | 1306 / 1307 | 5208 | 4725 | 9 / 2 | +0.357 | 0.158 |
| [06 Q8.14](variants/06_q8_14/) | 22 / 14 | 0.132865 | 1270 / 1271 | 4894 | 4371 | 8.5 / 1 | +0.167 | 0.151 |
| [07 Q8.12](variants/07_q8_12/) | 20 / 12 | 0.131730 | 1234 / 1235 | 4447 | 3995 | 7.5 / 1 | +0.284 | 0.146 |

세 BKF L=1 구현 모두 저장된 OOC report에서 100 MHz setup을 통과함. Power는 vectorless estimate임. 전체 configuration의 수치 오차, 검증 근거와 비트폭별 report는 [BITWIDTH_COMPARISON.md](BITWIDTH_COMPARISON.md)에 있음.

각 variant는 다음 공통 구조를 가짐. 명목 regression에 필요한 소스와 vector는 variant 안에 있고, `04`/`05`의 단계 간 equivalence test는 직전 sibling variant를 reference로 사용함.

- `rtl/`: synthesizable Verilog-2001와 LUT initialization file
- `tb/`: unit/integration SystemVerilog testbench
- `vectors/`: 500-step deterministic nominal vectors
- `python/`: reference model, vector generator, RTL comparator
- `scripts/`: Icarus와 Vivado batch runner
- `constraints/`: 100 MHz OOC clock constraint
- `config/`: Python reference/vector의 실행 조건. `01`–`05`는 Q8.16 RTL과의 호환성을 검증하고, `06`/`07`은 W/F 계약 검증 후 RTL 형식 헤더를 생성함
- `Makefile`: 해당 variant의 regression target (`04`/`05` 단계 간 비교는 sibling variant 필요)

`validation/final_waveform/`은 `05`의 RTL·TB·vector를 사용하는 별도 observer와 검증 실행기임. `results/`에는 공개용 결과를 모으고 variant별 중간 산출물과 재생성 VCD는 Git에서 제외함.

## 실행

Python 3와 Icarus Verilog(`iverilog`, `vvp`)가 필요하며 plot 생성에는 Matplotlib이 필요함. Bash script를 사용하므로 Windows simulation은 WSL 또는 Git Bash 환경을 권장함.

루트에서는 최종 variant가 기본값임.

```bash
make list
make setup
make test
make wave
make plots
```

`make plots`는 실제 RTL CSV가 없거나 500-step reference와 행 수가 다르면 실패함. fixed-point reference를 RTL 결과로 대체하지 않으므로 처음에는 `make test` 후 `make plots`를 실행해야 함.

다른 단계를 실행하려면 `VARIANT` 지정이 필요함.

```bash
make test VARIANT=03_divider_pipeline
make wave VARIANT=01_baseline
```

비트폭 실험과 Q8.16 호환성 재검증:

```bash
make bitwidth VARIANT=06_q8_14
make bitwidth VARIANT=07_q8_12
make test-q8-16-regression VARIANT=06_q8_14
```

최종 Q8.16 파형 검증은 네 configuration에서 baseline/full/debug 각각 500-step을 실행함. Full VCD는 500-step, debug VCD는 앞 10-step을 기록하며 두 모드 모두 500-step 수치 검증을 마침.

```bash
make wave-final
make verify-wave-final
```

실행 경로와 신호 설명은 [최종 파형 검증 안내](validation/final_waveform/README.md)에 있음.

Vivado batch 실행:

```bash
make vivado \
  VARIANT=05_ekf_overflow_pipeline \
  TARGET_FPGA_PART=xc7z020clg400-1 \
  VIVADO_CONFIG=all
```

`VIVADO_CONFIG`는 `all`, `ekf_l1`, `bkf_l1`, `rbkf_l1`, `rbkf_l8` 중 하나임. Vivado Tcl은 Windows에서도 직접 실행 가능함.

## 검증 범위와 제한

- `03` → `04`, `04` → `05` 단계 간 4 configuration × 500-step × 19-field trace mismatch 0
- `04`/`05` EKF overflow 전후 directed 21, randomized 2,000 포함 2,073 paired transaction semantic mismatch 0
- nominal overflow/solver error 0, negative posterior covariance diagonal 0
- `06`/`07`에서도 네 configuration의 one-step/500-step RTL과 해당 비트폭의 Python reference가 일치함
- 저장된 VCD는 baseline의 EKF, BKF L=1, rBKF L=8 5-step smoke waveform이며, 최종 Q8.16 full/debug 검증은 실행기와 compact evidence를 제공함
- 최종 파형 검증은 네 configuration × 세 모드 = 6,000 update의 수치·CSV·handshake·latency를 확인함
- 실제 comparator/1-bit ADC, RTL Jacobian generator, bus/DDR wrapper는 포함하지 않음
- Vivado 결과는 OOC core 비교이며 bitstream과 board validation은 수행하지 않음
- 검증 범위는 단일 deterministic nominal sequence와 rBKF L=1/L=8
