# EKF-overflow-pipelined RTL Vivado results

공통 조건: Vivado `2020.2`, target part `xc7z020clg400-1`, clock period `10.000 ns` (100 MHz), post-route임. Power는 vectorless `Total On-Chip Power` 추정값이며 report confidence는 `Medium`임.

| Algorithm | LUT | FF | BRAM Tile | DSP | WNS (ns) | WHS (ns) | WPWS (ns) | Power (W) |
| --- | --: | --: | --: | --: | --: | --: | --: | --: |
| EKF | 5349 | 4860 | 9 | 2 | 0.097 | 0.124 | 4.500 | 0.166 |
| BKF L=1 | 5208 | 4725 | 9 | 2 | 0.357 | 0.124 | 4.500 | 0.158 |
| rBKF L=1 | 5208 | 4725 | 9 | 2 | 0.357 | 0.124 | 4.500 | 0.158 |
| rBKF L=8 | 5343 | 4749 | 9 | 2 | 0.218 | 0.125 | 4.500 | 0.158 |
