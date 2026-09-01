VARIANT ?= 05_ekf_overflow_pipeline
VARIANT_DIR := variants/$(VARIANT)
TARGET_FPGA_PART ?= xc7z020clg400-1
VIVADO_CONFIG ?= all

.PHONY: help list check-variant all setup vectors lint test-unit test-ekf test-bkf \
	test-rbkf-l1 test-rbkf-l8 test wave wave-ekf wave-bkf wave-rbkf plots vivado clean-sim

help:
	@echo "Use VARIANT=<name>; default: $(VARIANT)"
	@echo "Targets: list, setup, vectors, lint, test, wave, plots, vivado, clean-sim"

list:
	@find variants -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort

check-variant:
	@test -d "$(VARIANT_DIR)" || (echo "Unknown variant: $(VARIANT)" >&2; exit 2)

all setup vectors lint test-unit test-ekf test-bkf test-rbkf-l1 test-rbkf-l8 test \
wave wave-ekf wave-bkf wave-rbkf plots clean-sim: check-variant
	$(MAKE) -C "$(VARIANT_DIR)" $@

vivado: check-variant
	$(MAKE) -C "$(VARIANT_DIR)" vivado \
		TARGET_FPGA_PART="$(TARGET_FPGA_PART)" VIVADO_CONFIG="$(VIVADO_CONFIG)"
