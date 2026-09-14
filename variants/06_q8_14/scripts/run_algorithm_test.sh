#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p results/rtl results/waveform

algorithm="${1:?algorithm is required}"
steps="${2:-500}"
wave_mode="${3:-}"
if [[ ! "$steps" =~ ^[0-9]+$ ]] || (( steps < 1 || steps > 500 )); then
  echo "STEPS must be an integer in 1..500" >&2
  exit 2
fi
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
    result_name=ekf
    top=tb_ekf_full
    output=results/rtl/tb_ekf_full.vvp
    extra_sources=(rtl/ekf/ekf_core.v tb/integration/tb_ekf_full.sv)
    parameter_arg=""
    ;;
  bkf)
    result_name=bkf_l1
    top=tb_bkf_full
    output=results/rtl/tb_bkf_full.vvp
    extra_sources=(tb/integration/tb_bkf_full.sv)
    parameter_arg=""
    ;;
  rbkf_l1)
    result_name=rbkf_l1
    top=tb_rbkf_full
    output=results/rtl/tb_rbkf_l1.vvp
    extra_sources=(rtl/rbkf/rbkf_core.v tb/integration/tb_rbkf_full.sv)
    parameter_arg="-Ptb_rbkf_full.NUM_BRANCHES=1"
    ;;
  rbkf_l8)
    result_name=rbkf_l8
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

# Remove stale output before each non-wave run so partial/failing runs remain visible.
if [[ "$wave_mode" != "wave" ]]; then
  rm -f "results/rtl_${result_name}_outputs.csv" "results/cycle_counts_${result_name}.csv"
fi

iverilog -g2012 -gstrict-expr-width -Wall -Wno-sensitivity-entire-array -Wimplicit \
  -DWAVE_DEBUG -DWNS_CLOSURE_ASSERTIONS -I. \
  ${parameter_arg:+$parameter_arg} -s "$top" -o "$output" "${common_sources[@]}" "${extra_sources[@]}"

if [[ "$wave_mode" == "wave" ]]; then
  vvp "$output" "+STEPS=${steps}" +WAVE
else
  vvp "$output" "+STEPS=${steps}"
fi

if [[ "$wave_mode" != "wave" ]]; then
  "${PYTHON_BIN:-python3}" - "$result_name" "$steps" <<'PY_CHECK'
import csv
import pathlib
import sys
name, expected = sys.argv[1], int(sys.argv[2])
for filename in (f"rtl_{name}_outputs.csv", f"cycle_counts_{name}.csv"):
    path = pathlib.Path("results") / filename
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != expected or [int(row["step"]) for row in rows] != list(range(expected)):
        raise SystemExit(f"FAIL: missing/duplicate/out-of-order completed rows in {path}: {len(rows)}/{expected}")
    for index, row in enumerate(rows):
        if None in row or any(value is None or not value.lstrip("-").isdigit() for value in row.values()):
            raise SystemExit(f"FAIL: malformed/X/Z output in {path} row {index}")
    if filename.startswith("rtl_"):
        for flag in ("overflow", "numeric_error", "solver_error"):
            if flag not in rows[0] or any(int(row[flag]) not in (0, 1) for row in rows):
                raise SystemExit(f"FAIL: invalid or absent {flag} in {path}")
print(f"PASS: {name} complete, ordered, known-valued CSV rows={expected}")
PY_CHECK
fi
