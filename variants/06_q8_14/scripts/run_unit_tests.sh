#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p results/rtl results/regression/after_divider_pipeline results/unit
summary=results/unit/status.csv
printf 'test,status\n' > "$summary"
failures=0
common_sources=(
  rtl/common/fx_divider_q8_16.v
  rtl/common/fx_determinant_finalize_pipeline.v
  rtl/common/fx_mul_mac_pipeline.v
  rtl/nonlinear/q8_16_rsqrt_lut.v
  rtl/nonlinear/arcsine_cov_lut_q8_16.v
  rtl/bkf/bkf_core.v
)
run_unit() {
  local top="$1"
  local language="$2"
  shift 2
  local log="results/unit/${top}.log"
  local status=PASS
  if ! iverilog "$language" -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit -I. \
      -s "$top" -o "results/rtl/${top}.vvp" "$@" > "$log" 2>&1; then
    status=COMPILE_FAIL
  elif ! vvp "results/rtl/${top}.vvp" \
      "+OUTPUT=results/unit/${top}_transactions.csv" >> "$log" 2>&1; then
    status=SIM_FAIL
  fi
  cat "$log"
  printf '%s,%s\n' "$top" "$status" >> "$summary"
  if [[ "$status" != PASS ]]; then failures=$((failures+1)); fi
}
run_unit tb_fx_divider_q8_16 -g2001 \
  rtl/common/fx_divider_q8_16.v tb/unit/tb_fx_divider_q8_16.v
if [[ -f results/unit/tb_fx_divider_q8_16_transactions.csv ]]; then
  cp results/unit/tb_fx_divider_q8_16_transactions.csv \
    results/regression/after_divider_pipeline/divider_transactions.csv
fi
run_unit tb_fx_determinant_finalize_pipeline -g2001 \
  rtl/common/fx_determinant_finalize_pipeline.v tb/unit/tb_fx_determinant_finalize_pipeline.v
run_unit tb_bkf_covariance_pipeline -g2012 \
  "${common_sources[@]}" tb/unit/tb_bkf_covariance_pipeline.sv
run_unit tb_ekf_overflow_pipeline -g2012 \
  "${common_sources[@]}" tb/unit/tb_ekf_overflow_pipeline.sv
run_unit tb_q8_16_arithmetic -g2001 \
  rtl/arithmetic/q8_16_add_sat.v rtl/arithmetic/q8_16_sub_sat.v \
  rtl/arithmetic/q8_16_mul_sat.v rtl/arithmetic/q8_16_mac3_sat.v \
  tb/unit/tb_q8_16_arithmetic.v
run_unit tb_q8_16_nonlinear_luts -g2001 \
  rtl/nonlinear/q8_16_rsqrt_lut.v rtl/nonlinear/arcsine_cov_lut_q8_16.v \
  tb/unit/tb_q8_16_nonlinear_luts.v
run_unit tb_q8_16_matrix -g2001 \
  rtl/arithmetic/q8_16_sub_sat.v rtl/arithmetic/q8_16_mul_sat.v \
  rtl/arithmetic/q8_16_mac3_sat.v rtl/common/fx_divider_q8_16.v \
  rtl/matrix/q8_16_matmul3.v rtl/matrix/mat3_inverse_q8_16.v tb/unit/tb_q8_16_matrix.v
run_unit tb_bkf_handshake -g2012 "${common_sources[@]}" tb/integration/tb_bkf_handshake.sv
run_unit tb_ekf_handshake -g2012 "${common_sources[@]}" rtl/ekf/ekf_core.v tb/integration/tb_ekf_handshake.sv
if (( failures )); then
  echo "FAIL: ${failures} unit regressions failed; all independent units were attempted"
  exit 1
fi
echo "PASS: all 9 arithmetic/nonlinear/matrix/determinant/covariance/overflow/handshake regressions"
