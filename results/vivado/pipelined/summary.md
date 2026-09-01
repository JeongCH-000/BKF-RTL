# Pipelined RTL Vivado results

공통 조건: Vivado `2020.2`, target part `xc7z020clg400-1`, clock period `10.000 ns` (100 MHz), post-route임. Power는 vectorless `Total On-Chip Power` 추정값이며 report confidence는 `Medium`임.

| Algorithm | LUT | FF | BRAM Tile | DSP | WNS (ns) | WHS (ns) | WPWS (ns) | Power (W) |
| --- | --: | --: | --: | --: | --: | --: | --: | --: |
| EKF | 4503 | 4131 | 9 | 2 | -3.439 | 0.110 | 4.500 | 0.153 |
| BKF L=1 | 4357 | 4004 | 9 | 2 | -3.212 | 0.155 | 4.500 | 0.150 |
| rBKF L=1 | 4357 | 4004 | 9 | 2 | -3.212 | 0.155 | 4.500 | 0.150 |
| rBKF L=8 | 4466 | 4036 | 9 | 2 | -3.419 | 0.153 | 4.500 | 0.151 |
