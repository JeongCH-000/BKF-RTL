#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
if [[ ! -x "$PYTHON_BIN" ]]; then
  python3 -m venv .venv
  .venv/bin/python -m pip install -r requirements.txt
  PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
fi
exec "$PYTHON_BIN" python/run_bitwidth_experiment.py
