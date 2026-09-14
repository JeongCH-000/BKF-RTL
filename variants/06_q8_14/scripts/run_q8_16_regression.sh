#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Set up this project's Python environment first: make setup" >&2
  exit 2
fi
exec "$PYTHON_BIN" "$ROOT_DIR/python/run_q8_16_regression.py" "$@"
