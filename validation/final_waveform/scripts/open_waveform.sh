#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
design="${1:-bkf_l1}"
mode="${2:-full}"
case "$design" in ekf_l1|bkf_l1|rbkf_l1|rbkf_l8) ;; *) echo "Invalid design: $design" >&2; exit 2;; esac
case "$mode" in full) file=".work/waveforms/full/${design}.vcd";; debug) file=".work/waveforms/debug/${design}_debug.vcd";; *) echo "Mode must be full or debug" >&2; exit 2;; esac
[[ -f "$file" ]] || { echo "Missing $file; run make wave_$design" >&2; exit 2; }
if command -v surfer >/dev/null 2>&1; then
  exec surfer "$file"
elif command -v gtkwave >/dev/null 2>&1; then
  exec gtkwave "$file"
elif [[ "$(uname -s)" == Darwin ]] && [[ -d /Applications/gtkwave.app ]]; then
  exec open -a /Applications/gtkwave.app "$file"
else
  echo "No waveform viewer found. Install Surfer or GTKWave." >&2
  exit 2
fi
