# Divider-pipelined RTL Vivado results

공통 조건: Vivado `2020.2`, target part `xc7z020clg400-1`, clock period `10.000 ns` (100 MHz), post-route임. Power는 vectorless `Total On-Chip Power` 추정값이며 report confidence는 `Medium`임.

| Algorithm | LUT | FF | BRAM Tile | DSP | WNS (ns) | WHS (ns) | WPWS (ns) | Power (W) |
| --- | --: | --: | --: | --: | --: | --: | --: | --: |
| EKF | 4248 | 4305 | 9 | 2 | -1.360 | 0.122 | 4.500 | 0.147 |
| BKF L=1 | 4283 | 4170 | 9 | 2 | -0.631 | 0.143 | 4.500 | 0.152 |
| rBKF L=1 | 4283 | 4170 | 9 | 2 | -0.631 | 0.143 | 4.500 | 0.152 |
| rBKF L=8 | 4347 | 4197 | 9 | 2 | -0.781 | 0.149 | 4.500 | 0.150 |
