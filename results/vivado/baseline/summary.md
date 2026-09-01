# Vivado baseline results

공통 조건: Vivado `2020.2`, target part `xc7z020clg400-1`, clock period `10.000 ns` (100 MHz), out-of-context synthesis임. 아래 `Fully Placed` 표의 implementation 수치는 post-route 수치가 아니며, 별도 post-route 값은 마지막 표에 기록함.

## Post-synthesis utilization

| Algorithm | Slice LUTs | FF | BRAM Tile | DSP |
| --- | --: | --: | --: | --: |
| EKF, ideal, L=1 | 4415 | 3851 | 9 | 2 |
| BKF, L=1 | 4206 | 3698 | 9 | 2 |
| rBKF, L=1 | 4206 | 3698 | 9 | 2 |
| rBKF, L=8 | 4340 | 3732 | 9 | 2 |

## Fully Placed utilization, timing, and power

| Algorithm | Slice LUTs | FF | Slice | BRAM Tile | DSP | WNS (ns) | WHS (ns) | WPWS (ns) | On-Chip Power (W) | 100 MHz setup |
| --- | --: | --: | --: | --: | --: | --: | --: | --: | --: | --- |
| EKF, ideal, L=1 | 4470 | 3851 | 1771 | 9 | 2 | -15.808 | 0.156 | 4.500 | 0.190 | Fail |
| BKF, L=1 | 4193 | 3698 | 1676 | 9 | 2 | -15.217 | 0.155 | 4.500 | 0.188 | Fail |
| rBKF, L=1 | 4193 | 3698 | 1676 | 9 | 2 | -15.217 | 0.155 | 4.500 | 0.188 | Fail |
| rBKF, L=8 | 4341 | 3732 | 1714 | 9 | 2 | -15.142 | 0.136 | 4.500 | 0.187 | Fail |

## Measured non-Vivado schedule

아래 latency는 500-step Icarus regression에서 model/input acceptance부터 `result_valid`까지 측정함. initiation interval은 동일 regression에서 연속한 model/input acceptance cycle의 차이임.

| Algorithm | Cycles/update | Latency (cycles) | Initiation interval (cycles) | Updates/s |
| --- | --: | --: | --: | --: |
| EKF, ideal, L=1 | 620 | 620 | 621 | Not measured |
| BKF, L=1 | 654 | 654 | 655 | Not measured |
| rBKF, L=1 | 654 | 654 | 655 | Not measured |
| rBKF, L=8 | 669 | 669 | 670 | Not measured |

100 MHz에서 네 구성 모두 setup timing을 만족하지 못했으므로 Icarus initiation interval만으로 FPGA `Updates/s`를 산출하지 않음.

## Post-route and unmeasured fields

Post-route power는 vectorless `Total On-Chip Power` 추정값이며 report confidence는 `Medium`임.

| Algorithm | Fmax | TNS (ns) | Post-route utilization (LUT / FF / Slice / BRAM / DSP) | Post-route power (W) | Energy/update |
| --- | --: | --: | --: | --: | --: |
| EKF, ideal, L=1 | Not measured | -32358.031 | 4507 / 3885 / 1783 / 9 / 2 | 0.190 | Not measured |
| BKF, L=1 | Not measured | -32706.703 | 4244 / 3745 / 1699 / 9 / 2 | 0.188 | Not measured |
| rBKF, L=1 | Not measured | -32706.703 | 4244 / 3745 / 1699 / 9 / 2 | 0.188 | Not measured |
| rBKF, L=8 | Not measured | -32405.221 | 4407 / 3792 / 1734 / 9 / 2 | 0.187 | Not measured |

`Fmax`는 clock constraint sweep으로 측정하지 않았고, `Energy/update`는 achieved clock/throughput과 activity 기반 power가 없어 산출하지 않음. WNS로부터 근삿값을 추정하지 않음.
