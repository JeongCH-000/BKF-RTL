# WNS-closure RTL Vivado results

공통 조건: Vivado `2020.2`, target part `xc7z020clg400-1`, clock period `10.000 ns` (100 MHz), post-route임. Power는 vectorless `Total On-Chip Power` 추정값이며 report confidence는 `Medium`임.

| Algorithm | LUT | FF | BRAM Tile | DSP | WNS (ns) | WHS (ns) | WPWS (ns) | Power (W) |
| --- | --: | --: | --: | --: | --: | --: | --: | --: |
| EKF | 5329 | 4861 | 9 | 2 | -0.401 | 0.098 | 4.500 | 0.164 |
| BKF L=1 | 5184 | 4720 | 9 | 2 | 0.095 | 0.096 | 4.500 | 0.156 |
| rBKF L=1 | 5184 | 4720 | 9 | 2 | 0.095 | 0.096 | 4.500 | 0.156 |
| rBKF L=8 | 5319 | 4750 | 9 | 2 | 0.115 | 0.110 | 4.500 | 0.159 |
