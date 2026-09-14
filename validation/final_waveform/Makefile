PYTHON ?= .venv/bin/python

.PHONY: all setup wave_all wave_ekf_l1 wave_bkf_l1 wave_rbkf_l1 wave_rbkf_l8 verify verify-evidence test-validator
all: wave_all

setup:
	@test -x "$(PYTHON)" || python3 -m venv .venv
	@"$(PYTHON)" -c 'import numpy' 2>/dev/null || "$(PYTHON)" -m pip install -r requirements-waveforms.txt

wave_all: setup
	PYTHON_BIN="$(PYTHON)" ./scripts/run_waveforms.sh all

wave_ekf_l1 wave_bkf_l1 wave_rbkf_l1 wave_rbkf_l8: setup
	PYTHON_BIN="$(PYTHON)" ./scripts/run_waveforms.sh $(patsubst wave_%,%,$@)

verify: setup
	PYTHON_BIN="$(PYTHON)" ./scripts/run_waveforms.sh all --verify-only

verify-evidence: setup
	PYTHON_BIN="$(PYTHON)" ./scripts/run_waveforms.sh all --evidence-only

test-validator: setup
	"$(PYTHON)" python/test_waveform_validation.py
