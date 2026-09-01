#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p results/rtl results/waveform

algorithm="${1:?algorithm is required}"
steps="${2:-500}"
wave_mode="${3:-}"
common_sources=(
  rtl/common/fx_divider_q8_16.v
  rtl/common/fx_determinant_finalize_pipeline.v
  rtl/common/fx_mul_mac_pipeline.v
  rtl/nonlinear/q8_16_rsqrt_lut.v
  rtl/nonlinear/arcsine_cov_lut_q8_16.v
  rtl/bkf/bkf_core.v
)

case "$algorithm" in
  ekf)
    top=tb_ekf_full
    output=results/rtl/tb_ekf_full.vvp
    extra_sources=(rtl/ekf/ekf_core.v tb/integration/tb_ekf_full.sv)
    parameter_arg=""
    ;;
  bkf)
    top=tb_bkf_full
    output=results/rtl/tb_bkf_full.vvp
    extra_sources=(tb/integration/tb_bkf_full.sv)
    parameter_arg=""
    ;;
  rbkf_l1)
    top=tb_rbkf_full
    output=results/rtl/tb_rbkf_l1.vvp
    extra_sources=(rtl/rbkf/rbkf_core.v tb/integration/tb_rbkf_full.sv)
    parameter_arg="-Ptb_rbkf_full.NUM_BRANCHES=1"
    ;;
  rbkf_l8)
    top=tb_rbkf_full
    output=results/rtl/tb_rbkf_l8.vvp
    extra_sources=(rtl/rbkf/rbkf_core.v tb/integration/tb_rbkf_full.sv)
    parameter_arg="-Ptb_rbkf_full.NUM_BRANCHES=8"
    ;;
  *)
    echo "unknown algorithm: $algorithm" >&2
    exit 2
    ;;
esac

iverilog -g2012 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit \
  -DWAVE_DEBUG -DWNS_CLOSURE_ASSERTIONS -I. \
  ${parameter_arg:+$parameter_arg} -s "$top" -o "$output" "${common_sources[@]}" "${extra_sources[@]}"

if [[ "$wave_mode" == "wave" ]]; then
  vvp "$output" "+STEPS=${steps}" +WAVE
else
  vvp "$output" "+STEPS=${steps}"
fi
