# Final RTL waveform validation

`Project/final_waveform_validation`의 최종 500-step waveform 검증을 공개 저장소 구조에 맞춰 옮긴 실행 도구다.
기존 [`05_ekf_overflow_pipeline`](../../variants/05_ekf_overflow_pipeline/)의 RTL, integration testbench,
입력 벡터와 Python 모델을 재사용한다. 추가 observer는 DUT/testbench의 신호를 읽기만 한다.

## 실행

Python 3.12 이상, NumPy 2.5.1, Icarus Verilog (`iverilog`, `vvp`), Bash, Make가 필요하다.
Mac/Linux에서 실행하며 `make setup`이 이 폴더의 `.venv`에 NumPy를 설치한다.

```bash
# 저장소 최상위에서
make wave-final              # 네 설계 × baseline/full/debug × 500-step
make verify-wave-final       # 위 명령으로 생성한 VCD/CSV/log 재검사

# 이 폴더에서
make setup
make wave_all                # make all도 동일
make wave_ekf_l1
make wave_bkf_l1
make wave_rbkf_l1
make wave_rbkf_l8
make verify
make verify-evidence         # 저장된 CSV 및 Python reference 검사; VCD/simulator 불필요
make test-validator          # cycle CSV/VCD timescale 변조 탐지 검사; simulator 불필요

./scripts/run_waveforms.sh all --debug-steps 20
./scripts/run_waveforms.sh all --debug-steps 20 --verify-only
./scripts/open_waveform.sh bkf_l1 full
./scripts/open_waveform.sh rbkf_l8 debug
```

`PYTHON=/absolute/path/to/python`으로 기존 NumPy 환경을 선택할 수 있다.
직접 스크립트를 실행할 때는 `PYTHON_BIN`을 사용한다.
Debug 기록 길이는 5–20-step이고 기본값은 10이다. `--verify-only`에서도 생성할 때와 같은 길이를 지정한다.

전체 simulation은 모든 모드에서 500-step이다. Full은 500-step의 주요 interface 신호를,
debug는 앞 10-step의 내부 pipeline·행렬 신호를 기록한다. 기존 `+WAVE` 5-step smoke 모드와 별도로 동작한다.
`verify`는 생성된 파일이 있어야 하며, 새 checkout에서는 `wave_all`을 먼저 실행하거나 `verify-evidence`를 사용한다.

## 저장소 구조와 재현성

| 경로 | 내용 |
| --- | --- |
| `tb/waveform/waveform_capture.sv` | 원본 waveform observer; 별도 simulation top |
| `python/run_waveform_validation.py` | 세 모드 실행, CSV/Python/VCD/source hash 검증 |
| `scripts/` | 실행 wrapper와 Surfer/GTKWave opener |
| `.work/` | 자동 생성 작업 공간; Git 제외 |
| `.work/waveforms/{full,debug}/` | 생성된 VCD 8개 |
| `.work/results/validation/` | 실행별 CSV와 최신 JSON summary |
| `.work/results/logs/` | compile 및 simulation 로그 |
| [`../../results/waveforms/final/`](../../results/waveforms/final/) | 추적하는 원본 결과와 재검증 요약 |

실행 시 `.work/`에서 variant의 `rtl/`, `tb/`, `vectors/`를 상대 symlink로 참조하고,
기존 `run_algorithm_test.sh`를 작업 공간으로 복사해 baseline을 실행한다. 생성물은 `.work/`에 저장된다.
500-step 입력 및 expected `.mem`, RTL/include/LUT, integration TB는 원본 SHA-256으로 검사한다.
Read-only observer도 원본 SHA-256으로 검사하고 Python/config/simulation script의 실행 전후 hash를 비교한다.

원본 NPZ를 중복 보관하는 대신 현재 variant 모델로 stimulus와 fixed trace를 재계산하고,
[`reference_manifest.json`](../../results/waveforms/final/reference_manifest.json)의 배열별 shape/dtype/SHA-256과 비교한다.
정수 trace 13개 field와 원래 stimulus가 모두 일치해야 한다. 배열 hash는 little-endian C-order bytes 기준이다.
수치가 동일함을 확인한 다음, 모든 모드의 output/cycle CSV를 원본 500-row CSV 전체와 비교한다.
Cycle CSV의 step 순서와 `result_cycle - start_cycle == cycles`를 확인하고,
VCD는 명시된 timescale이 `1ps`인지 검사한 뒤 timestamp를 해석한다.
이 과정에서 벡터·LUT·reference 원본을 재생성하지 않는다.

## 검증 결과

원본 검증은 2026-09-11에 Python 3.12.6, NumPy 2.5.1, Icarus Verilog 13.0으로 수행됐다.
원본 수치와 VCD의 hash·크기·timestamp는 [`summary.json`](../../results/waveforms/final/summary.json)에 보존했다.
2026-09-14 공개 저장소의 전체 waveform 재실행과 `make verify-wave-final`도 통과했다.
새 실행의 수치 및 실행 전후 source audit는 [`repository_validation.json`](../../results/waveforms/final/repository_validation.json)에 있다.

| Design | Simulation | State/cov mismatch | TB latency | II | VCD edge latency |
| --- | --- | ---: | ---: | ---: | ---: |
| EKF L=1 | 3 × 500-step PASS | 0 / 0 | 1236 | 1237 | 1235 |
| BKF L=1 | 3 × 500-step PASS | 0 / 0 | 1306 | 1307 | 1305 |
| rBKF L=1 | 3 × 500-step PASS | 0 / 0 | 1306 | 1307 | 1305 |
| rBKF L=8 | 3 × 500-step PASS | 0 / 0 | 1342 | 1343 | 1341 |

Cycle 단위이며 clock period는 10 ns다. TB latency는 acceptance cycle을 포함하므로
acceptance edge → `result_valid` edge의 간격보다 1 cycle 크다.
Full VCD의 입력/출력 handshake는 각각 500개, 기본 debug는 각각 10개다.
모든 result pulse에서 state/covariance payload가 expected vector와 같고,
`overflow_flag`, `numeric_error`, `solver_error`는 0이며 `done`이 정렬된다.

새 실행의 VCD hash에는 생성 시각 등 header 차이가 반영될 수 있다.
기록된 payload·handshake·latency를 검사하며 원본 VCD의 파일 hash 자체를 요구하지 않는다.
원본 약 100 MB의 full/debug VCD, `.vvp`, 가상환경, NPZ, 중복 모드별 CSV는 Git에 포함하지 않는다.
이 workflow는 RTL simulation 검증이며 Vivado timing/power를 새로 측정하지 않는다.

## Waveform 신호

Full의 `waveform_capture` scope는 주요 신호 32개다. Debug에는 DUT hierarchy와 unpacked array의 read-only alias가 추가된다.

| 목적 | 주요 신호 |
| --- | --- |
| Clock/reset | `clk`, `rst_n` (active-low) |
| 초기 상태·covariance | `cfg_valid`, `cfg_ready`, `cfg_state_flat`, `cfg_cov_flat` |
| 입력 모델 | `input_valid`, `input_ready`, `f_input_flat` |
| 측정/관측 | `measurement_flat`, `threshold_valid`, `threshold_ready`, `threshold_flat`, `observation_valid`, `observation_ready`, `branch_observation_bits` |
| 완료 및 상태 | `result_valid`, `result_ready`, `done`, `busy`, `fsm_state` |
| State/covariance | `state_out_flat`, `state_x/y/z`, `cov_out_flat`, `cov_00/11/22` |
| Error | `overflow_flag`, `numeric_error`, `solver_error` |
| Debug MAC/pipeline | `mul_request_valid/ready`, `pipe_result_valid/ready`, `pipe_mac_sum`, `pipeline_stage1/2/3_valid` |
| Debug divider/determinant | `divider_start/busy/valid`, `divider_quotient`, `det_capture_stage_valid`, `det_round_stage_valid`, `det_floor_stage_valid` |
| Debug local overflow | `cov_predict_overflow_local_valid_reg`, `cov_predict_overflow_local_reg` |
| Debug branch/array | `branch_reduction_valid`, `branch_observation_hold`, `vector_element[i].*`, `matrix_element[i].*` |

Observer의 `input_valid/input_ready`는 engine의 `model_valid/model_ready`다.
BKF/rBKF의 `measurement_flat`은 비활성 포트이고 실제 관측은 `branch_observation_bits`다.
`branch_index`는 procedural loop index이므로 순차 branch FSM으로 해석하지 않는다.

| Design | Integration testbench | 공유 engine hierarchy |
| --- | --- | --- |
| EKF L=1 | `tb_ekf_full` | `tb_ekf_full.dut.u_engine` |
| BKF L=1 | `tb_bkf_full` | `tb_bkf_full.dut` |
| rBKF L=1/L=8 | `tb_rbkf_full` | `tb_rbkf_full.dut.u_engine` |

기존 BKF testbench는 공개 wrapper `bkf_l1_core` 대신 `bkf_core`를 직접 instantiate한다.
24-bit Q8.16 값은 signed integer를 65536으로 나눈다. Matrix는 row-major이고 원소 0은 `[23:0]`이다.
Branch bit 순서는 `branch*3 + feature`, `1=+1`, `0=-1`이다.
Debug의 마지막 `$dumpoff` X 값은 기록 종료 표시이며 이후 500-step 검증은 계속된다.
