PYTHON ?= .venv/bin/python
VIVADO ?= vivado
TARGET_FPGA_PART ?= xc7z020clg400-1
VIVADO_CONFIG ?= all

.PHONY: all setup vectors lint test-unit test-ekf test-bkf test-rbkf-l1 test-rbkf-l8 \
	test wave wave-ekf wave-bkf wave-rbkf plots vivado clean-sim

all: test plots

setup:
	@test -x $(PYTHON) || (python3 -m venv .venv && $(PYTHON) -m pip install -r requirements.txt)

vectors: setup
	$(PYTHON) python/nominal_models.py
	$(PYTHON) python/test_reference_models.py
	$(PYTHON) python/generate_luts.py
	$(PYTHON) python/generate_nominal_vectors.py
	$(PYTHON) python/generate_unit_vectors.py

lint: setup
	$(PYTHON) python/lint_rtl.py

test-unit: vectors
	./scripts/run_unit_tests.sh

test-ekf: vectors
	./scripts/run_algorithm_test.sh ekf 1
	./scripts/run_algorithm_test.sh ekf 500

test-bkf: vectors
	./scripts/run_algorithm_test.sh bkf 1
	./scripts/run_algorithm_test.sh bkf 500

test-rbkf-l1: vectors
	./scripts/run_algorithm_test.sh rbkf_l1 1
	./scripts/run_algorithm_test.sh rbkf_l1 500

test-rbkf-l8: vectors
	./scripts/run_algorithm_test.sh rbkf_l8 1
	./scripts/run_algorithm_test.sh rbkf_l8 500

test: lint test-unit test-ekf test-bkf test-rbkf-l1 test-rbkf-l8
	$(PYTHON) python/compare_nominal_rtl.py

wave: wave-ekf wave-bkf wave-rbkf

wave-ekf: vectors
	./scripts/run_algorithm_test.sh ekf 5 wave

wave-bkf: vectors
	./scripts/run_algorithm_test.sh bkf 5 wave

wave-rbkf: vectors
	./scripts/run_algorithm_test.sh rbkf_l8 5 wave

plots: vectors
	$(PYTHON) python/plot_nominal_results.py

vivado:
	TARGET_FPGA_PART="$(TARGET_FPGA_PART)" VIVADO_CONFIG="$(VIVADO_CONFIG)" \
		$(VIVADO) -mode batch -source scripts/vivado/run_all.tcl

clean-sim:
	@if test -d results; then find results -type f \( -name '*.vvp' -o -name '*.vcd' -o -name '*.fst' \) -delete; fi
