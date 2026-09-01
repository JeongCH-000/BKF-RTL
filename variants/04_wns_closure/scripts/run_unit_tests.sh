#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p results/rtl \
  results/regression/after_divider_pipeline \
  results/regression/wns_equivalence

iverilog -g2001 -gstrict-expr-width -Wall -Wimplicit -I. \
  -s tb_fx_divider_q8_16 \
  -o results/rtl/tb_fx_divider_q8_16.vvp \
  rtl/common/fx_divider_q8_16.v \
  tb/unit/tb_fx_divider_q8_16.v
vvp results/rtl/tb_fx_divider_q8_16.vvp \
  +OUTPUT=results/regression/after_divider_pipeline/divider_transactions.csv

iverilog -g2001 -gstrict-expr-width -Wall -Wimplicit -I. \
  -s tb_fx_determinant_finalize_pipeline \
  -o results/rtl/tb_fx_determinant_finalize_pipeline.vvp \
  rtl/common/fx_determinant_finalize_pipeline.v \
  tb/unit/tb_fx_determinant_finalize_pipeline.v
vvp results/rtl/tb_fx_determinant_finalize_pipeline.vvp

iverilog -g2012 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit -I. \
  -s tb_bkf_covariance_pipeline \
  -o results/rtl/tb_bkf_covariance_pipeline.vvp \
  rtl/common/fx_divider_q8_16.v \
  rtl/common/fx_determinant_finalize_pipeline.v \
  rtl/common/fx_mul_mac_pipeline.v \
  rtl/nonlinear/q8_16_rsqrt_lut.v \
  rtl/nonlinear/arcsine_cov_lut_q8_16.v \
  rtl/bkf/bkf_core.v \
  tb/unit/tb_bkf_covariance_pipeline.sv
vvp results/rtl/tb_bkf_covariance_pipeline.vvp

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
  rtl/common/fx_determinant_finalize_pipeline.v \
  rtl/common/fx_mul_mac_pipeline.v \
  rtl/nonlinear/q8_16_rsqrt_lut.v \
  rtl/nonlinear/arcsine_cov_lut_q8_16.v \
  rtl/bkf/bkf_core.v

iverilog -g2012 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit -I. \
  -s tb_bkf_handshake -o results/rtl/tb_bkf_handshake.vvp \
  rtl/common/fx_divider_q8_16.v \
  rtl/common/fx_determinant_finalize_pipeline.v \
  rtl/common/fx_mul_mac_pipeline.v \
  rtl/nonlinear/q8_16_rsqrt_lut.v \
  rtl/nonlinear/arcsine_cov_lut_q8_16.v \
  rtl/bkf/bkf_core.v tb/integration/tb_bkf_handshake.sv
vvp results/rtl/tb_bkf_handshake.vvp

iverilog -g2012 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit -I. \
  -s tb_ekf_handshake -o results/rtl/tb_ekf_handshake.vvp \
  rtl/common/fx_divider_q8_16.v \
  rtl/common/fx_determinant_finalize_pipeline.v \
  rtl/common/fx_mul_mac_pipeline.v \
  rtl/nonlinear/q8_16_rsqrt_lut.v \
  rtl/nonlinear/arcsine_cov_lut_q8_16.v \
  rtl/bkf/bkf_core.v rtl/ekf/ekf_core.v tb/integration/tb_ekf_handshake.sv
vvp results/rtl/tb_ekf_handshake.vvp

compile_wns_equivalence() {
  local implementation="$1"
  local source_root="$2"
  local config="$3"
  local ekf_mode="$4"
  local num_branches="$5"
  local rtl_sources=("$source_root/rtl/common/fx_divider_q8_16.v")

  if [[ -f "$source_root/rtl/common/fx_determinant_finalize_pipeline.v" ]]; then
    rtl_sources+=("$source_root/rtl/common/fx_determinant_finalize_pipeline.v")
  fi
  rtl_sources+=(
    "$source_root/rtl/common/fx_mul_mac_pipeline.v"
    "$source_root/rtl/nonlinear/q8_16_rsqrt_lut.v"
    "$source_root/rtl/nonlinear/arcsine_cov_lut_q8_16.v"
    "$source_root/rtl/bkf/bkf_core.v"
  )

  iverilog -g2012 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit \
    -I"$source_root" -I. \
    -s tb_wns_equivalence \
    -Ptb_wns_equivalence.EKF_MODE="$ekf_mode" \
    -Ptb_wns_equivalence.NUM_BRANCHES="$num_branches" \
    -o "results/rtl/tb_wns_equivalence_${implementation}_${config}.vvp" \
    "${rtl_sources[@]}" \
    tb/integration/tb_wns_equivalence.sv
}

run_wns_equivalence_suite() {
  local implementation="$1"
  local source_root="$2"
  local trace_dir="results/regression/wns_equivalence/$implementation"

  mkdir -p "$trace_dir"

  compile_wns_equivalence "$implementation" "$source_root" ekf 1 1
  vvp "results/rtl/tb_wns_equivalence_${implementation}_ekf.vvp" \
    +STEPS=500 \
    "+OUTPUT=$trace_dir/ekf.csv"

  compile_wns_equivalence "$implementation" "$source_root" l1 0 1
  vvp "results/rtl/tb_wns_equivalence_${implementation}_l1.vvp" \
    +STEPS=500 \
    "+OUTPUT=$trace_dir/bkf_l1.csv"
  vvp "results/rtl/tb_wns_equivalence_${implementation}_l1.vvp" \
    +STEPS=500 \
    +RBKF_VECTOR_SET=1 \
    "+OUTPUT=$trace_dir/rbkf_l1.csv"

  compile_wns_equivalence "$implementation" "$source_root" l8 0 8
  vvp "results/rtl/tb_wns_equivalence_${implementation}_l8.vvp" \
    +STEPS=500 \
    "+OUTPUT=$trace_dir/rbkf_l8.csv"
}

run_wns_equivalence_suite reference ../03_divider_pipeline
run_wns_equivalence_suite current .

for config in ekf bkf_l1 rbkf_l1 rbkf_l8; do
  reference_trace="results/regression/wns_equivalence/reference/$config.csv"
  current_trace="results/regression/wns_equivalence/current/$config.csv"
  for trace in "$reference_trace" "$current_trace"; do
    if ! awk -F, 'NF != 19 { bad = 1 } END { exit (bad || NR != 501) }' "$trace"; then
      echo "FAIL: malformed WNS equivalence trace: $trace" >&2
      exit 1
    fi
  done
  if ! cmp "$reference_trace" "$current_trace"; then
    echo "FAIL: WNS equivalence mismatch for $config" >&2
    exit 1
  fi
done

echo "PASS: WNS equivalence reference=03_divider_pipeline current=04_wns_closure configs=4 fields=19 steps=500 mismatches=0"
echo "PASS: unit arithmetic/nonlinear/matrix/determinant/covariance plus BKF/EKF ready-valid tests"
