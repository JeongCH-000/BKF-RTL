# BKF_Verilog

Lorenz attractor의 3차원 상태 추정을 위한 EKF, 1-bit Bussgang Kalman Filter(BKF), reduced multi-branch BKF(rBKF)를 signed Q8.16 RTL로 구현하고 최적화한 프로젝트임. 합성 가능한 Verilog-2001, SystemVerilog testbench, deterministic vector, Python bit-accurate reference, Icarus regression, Vivado 2020.2 post-route 결과를 함께 제공함.

최종 권장 구현은 [`05_ekf_overflow_pipeline`](variants/05_ekf_overflow_pipeline/)임.

## 구현 범위

- EKF: full-resolution measurement를 사용하는 기준 구현
- BKF L=1: feature마다 1-bit observation 사용
- rBKF L=1: BKF와의 bit-exact equivalence 확인용
- rBKF L=8: 독립 noise를 가진 8개 branch bit를 feature별 평균
- Lorenz parameters: `sigma=10`, `rho=28`, `beta=8/3`, `dt=0.02`
- 실험 조건: seed `20260820`, 500 steps, `Q=1e-3 I`, `R=1e-1 I`

EKF와 BKF/rBKF는 observation resolution이 다르므로 RMSE는 동일 입력 해상도의 직접적인 우열 비교가 아니라 각 구현의 추정 품질 참고값임.

## 고정소수점 datapath

- signed 24-bit Q8.16
- round-to-nearest, exact ties away from zero
- rounding 후 signed 24-bit saturation
- 48-bit multiplier와 최소 50-bit three-term MAC accumulator
- 41-iteration restoring divider
- reciprocal-square-root 및 `(2/pi)asin(x)` LUT
- ready/valid handshake와 output backpressure 지원

Lorenz transition matrix `F_t`는 software에서 계산해 RTL에 입력.

## 개발 단계

표의 configuration 순서는 EKF / BKF L=1 / rBKF L=1 / rBKF L=8임.

MSE/RMSE, latency, 자원, WNS, power의 단계별 통합 비교는 [PIPELINING_COMPARISON.md](PIPELINING_COMPARISON.md)에서 확인 가능함.

| Variant | 핵심 변경 | Latency (cycles) | Vivado WNS (ns) | 100 MHz setup |
| --- | --- | --- | --- | --- |
| [01 Baseline](variants/01_baseline/) | Shared serial arithmetic/divider | 620 / 654 / 654 / 669 | -15.808 / -15.217 / -15.217 / -15.142 | 모두 Fail |
| [02 Pipelined](variants/02_pipelined/) | Operand → product → arithmetic → commit pipeline | 1169 / 1248 / 1248 / 1281 | -3.439 / -3.212 / -3.212 / -3.419 | 모두 Fail |
| [03 Divider pipeline](variants/03_divider_pipeline/) | Register-separated restoring divider | 1187 / 1266 / 1266 / 1299 | -1.360 / -0.631 / -0.631 / -0.781 | 모두 Fail |
| [04 WNS closure](variants/04_wns_closure/) | Determinant finalize와 covariance writeback pipeline | 1236 / 1306 / 1306 / 1342 | -0.401 / +0.095 / +0.095 / +0.115 | EKF만 Fail |
| [05 EKF overflow pipeline](variants/05_ekf_overflow_pipeline/) | EKF overflow predicate/sticky-status register separation | 1236 / 1306 / 1306 / 1342 | +0.097 / +0.357 / +0.357 / +0.218 | 모두 Pass |

각 variant는 독립 update를 겹쳐 실행하지 않는 single-issue 구조임. 최종 구현의 initiation interval은 각각 1237 / 1307 / 1307 / 1343 cycles임.

## 최종 Vivado 결과

공통 조건은 Vivado `2020.2`, `xc7z020clg400-1`, 10.000 ns clock, out-of-context implementation임.

| Configuration | LUT | FF | BRAM Tile | DSP | WNS (ns) | Power (W) |
| --- | --: | --: | --: | --: | --: | --: |
| EKF | 5349 | 4860 | 9 | 2 | +0.097 | 0.166 |
| BKF L=1 | 5208 | 4725 | 9 | 2 | +0.357 | 0.158 |
| rBKF L=1 | 5208 | 4725 | 9 | 2 | +0.357 | 0.158 |
| rBKF L=8 | 5343 | 4749 | 9 | 2 | +0.218 | 0.158 |

Power는 activity file을 사용하지 않은 vectorless estimate이며 Vivado confidence는 `Medium`임. 단계별 통합 비교는 [PIPELINING_COMPARISON.md](PIPELINING_COMPARISON.md), 상세 검증 결과와 원본 report는 [RESULTS.md](RESULTS.md)에 정리함.


각 variant는 다음 공통 구조를 가짐. 명목 regression에 필요한 소스와 vector는 variant 안에 있고, `04`/`05`의 단계 간 equivalence test는 직전 sibling variant를 reference로 사용함.

- `rtl/`: synthesizable Verilog-2001와 LUT initialization file
- `tb/`: unit/integration SystemVerilog testbench
- `vectors/`: 500-step deterministic nominal vectors
- `python/`: reference model, vector generator, RTL comparator
- `scripts/`: Icarus와 Vivado batch runner
- `constraints/`: 100 MHz OOC clock constraint
- `config/`: Python reference/vector의 실행 조건. 실행 시 RTL에 고정된 Q8.16, Q/R, 차원, branch 수와의 호환성을 검증함
- `Makefile`: 해당 variant의 regression target (`04`/`05` 단계 간 비교는 sibling variant 필요)

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
- 저장된 VCD는 baseline의 EKF, BKF L=1, rBKF L=8 5-step smoke waveform
- 실제 comparator/1-bit ADC, RTL Jacobian generator, bus/DDR wrapper는 포함하지 않음
- Vivado 결과는 OOC core 비교이며 bitstream과 board validation은 수행하지 않음
- 검증 범위는 단일 deterministic nominal sequence와 rBKF L=1/L=8

