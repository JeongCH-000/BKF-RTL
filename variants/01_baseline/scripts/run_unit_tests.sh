#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p results/rtl

iverilog -g2001 -gstrict-expr-width -Wall -Wimplicit -I. \
  -s tb_fx_divider_q8_16 \
  -o results/rtl/tb_fx_divider_q8_16.vvp \
  rtl/common/fx_divider_q8_16.v \
  tb/unit/tb_fx_divider_q8_16.v
vvp results/rtl/tb_fx_divider_q8_16.vvp

iverilog -g2001 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit \
  -s tb_q8_16_arithmetic \
  -o results/rtl/tb_q8_16_arithmetic.vvp \
  rtl/arithmetic/q8_16_add_sat.v \
  rtl/arithmetic/q8_16_sub_sat.v \
  rtl/arithmetic/q8_16_mul_sat.v \
  rtl/arithmetic/q8_16_mac3_sat.v \
  tb/unit/tb_q8_16_arithmetic.v
vvp results/rtl/tb_q8_16_arithmetic.vvp

iverilog -g2001 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit \
  -s tb_q8_16_nonlinear_luts \
  -o results/rtl/tb_q8_16_nonlinear_luts.vvp \
  rtl/nonlinear/q8_16_rsqrt_lut.v \
  rtl/nonlinear/arcsine_cov_lut_q8_16.v \
  tb/unit/tb_q8_16_nonlinear_luts.v
vvp results/rtl/tb_q8_16_nonlinear_luts.vvp

iverilog -g2001 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit \
  -s tb_q8_16_matrix \
  -o results/rtl/tb_q8_16_matrix.vvp \
  rtl/arithmetic/q8_16_sub_sat.v \
  rtl/arithmetic/q8_16_mul_sat.v \
  rtl/arithmetic/q8_16_mac3_sat.v \
  rtl/common/fx_divider_q8_16.v \
  rtl/matrix/q8_16_matmul3.v \
  rtl/matrix/mat3_inverse_q8_16.v \
  tb/unit/tb_q8_16_matrix.v
vvp results/rtl/tb_q8_16_matrix.vvp

iverilog -g2001 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit \
  -s bkf_core \
  -o results/rtl/bkf_core_elaboration.vvp \
  -I. \
  rtl/common/fx_divider_q8_16.v \
  rtl/nonlinear/q8_16_rsqrt_lut.v \
  rtl/nonlinear/arcsine_cov_lut_q8_16.v \
  rtl/bkf/bkf_core.v

iverilog -g2012 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit -I. \
  -s tb_bkf_handshake -o results/rtl/tb_bkf_handshake.vvp \
  rtl/common/fx_divider_q8_16.v \
  rtl/nonlinear/q8_16_rsqrt_lut.v \
  rtl/nonlinear/arcsine_cov_lut_q8_16.v \
  rtl/bkf/bkf_core.v tb/integration/tb_bkf_handshake.sv
vvp results/rtl/tb_bkf_handshake.vvp

iverilog -g2012 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit -I. \
  -s tb_ekf_handshake -o results/rtl/tb_ekf_handshake.vvp \
  rtl/common/fx_divider_q8_16.v \
  rtl/nonlinear/q8_16_rsqrt_lut.v \
  rtl/nonlinear/arcsine_cov_lut_q8_16.v \
  rtl/bkf/bkf_core.v rtl/ekf/ekf_core.v tb/integration/tb_ekf_handshake.sv
vvp results/rtl/tb_ekf_handshake.vvp

echo "PASS: unit arithmetic/nonlinear/matrix plus BKF/EKF ready-valid tests"
