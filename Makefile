VARIANT ?= 05_ekf_overflow_pipeline
VARIANT_DIR := variants/$(VARIANT)
TARGET_FPGA_PART ?= xc7z020clg400-1
VIVADO_CONFIG ?= all

.PHONY: help list check-variant check-bitwidth all setup vectors lint test-unit test-ekf test-bkf \
	test-rbkf-l1 test-rbkf-l8 test wave wave-ekf wave-bkf wave-rbkf plots vivado clean-sim \
	bitwidth format test-q8-16-regression wave-final verify-wave-final

help:
	@echo "Use VARIANT=<name>; default: $(VARIANT)"
	@echo "Targets: list, setup, vectors, lint, test, wave, plots, vivado, clean-sim"
	@echo "Bit-width variants: bitwidth, format, test-q8-16-regression (VARIANT=06_q8_14 or 07_q8_12)"
	@echo "Final Q8.16 waveform: wave-final, verify-wave-final"

list:
	@find variants -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort

check-variant:
	@test -d "$(VARIANT_DIR)" || (echo "Unknown variant: $(VARIANT)" >&2; exit 2)

check-bitwidth: check-variant
	@case "$(VARIANT)" in 06_q8_14|07_q8_12) ;; \
		*) echo "Use VARIANT=06_q8_14 or VARIANT=07_q8_12 for bit-width targets" >&2; exit 2 ;; esac

bitwidth format test-q8-16-regression: check-bitwidth
	$(MAKE) -C "$(VARIANT_DIR)" $@

all setup vectors lint test-unit test-ekf test-bkf test-rbkf-l1 test-rbkf-l8 test \
wave wave-ekf wave-bkf wave-rbkf plots clean-sim: check-variant
	$(MAKE) -C "$(VARIANT_DIR)" $@

vivado: check-variant
	$(MAKE) -C "$(VARIANT_DIR)" vivado \
		TARGET_FPGA_PART="$(TARGET_FPGA_PART)" VIVADO_CONFIG="$(VIVADO_CONFIG)"

wave-final:
	$(MAKE) -C validation/final_waveform wave_all

verify-wave-final:
	$(MAKE) -C validation/final_waveform verify
