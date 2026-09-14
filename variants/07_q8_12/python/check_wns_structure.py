#!/usr/bin/env python3
"""Static checks for the register boundaries required by WNS-closure work."""

from __future__ import annotations

import re

from common import ROOT
from nominal_config import validate_generated_header


def require(source: str, pattern: str, description: str, errors: list[str]) -> None:
    if re.search(pattern, source, flags=re.S) is None:
        errors.append(f"missing structure: {description}")


def strip_tcl_comments(source: str) -> str:
    """Remove line comments before checking active XDC/Tcl commands."""
    return re.sub(r"(?m)#.*$", "", source)


def main() -> None:
    validate_generated_header()
    errors: list[str] = []
    core_path = ROOT / "rtl" / "bkf" / "bkf_core.v"
    det_path = ROOT / "rtl" / "common" / "fx_determinant_finalize_pipeline.v"
    core = core_path.read_text(encoding="utf-8")
    determinant = det_path.read_text(encoding="utf-8")
    ekf_test = (ROOT / "tb" / "integration" / "tb_ekf_full.sv").read_text(
        encoding="utf-8"
    )
    equivalence_test = (
        ROOT / "tb" / "integration" / "tb_wns_equivalence.sv"
    ).read_text(encoding="utf-8")

    for signal in (
        "cov_predict_mac_accumulator_reg",
        "cov_predict_mac_write_mask_reg",
        "cov_predict_overflow_local_reg",
        "cov_predict_overflow_local_valid_reg",
        "add_q_operand_reg",
        "cov_sym_left_reg",
        "measurement_operand_reg",
        "measurement_sym_left_reg",
        "sign_sym_left_reg",
        "self_reduce_operand_reg",
        "ekf_sign_copy_operand_reg",
        "branch_observation_hold",
        "branch_reduction_valid",
    ):
        require(core, rf"\b{signal}\b", signal, errors)

    for state in (
        "ST_COV_OUTER_COMMIT",
        "ST_ADD_Q_COMMIT",
        "ST_SYM_SIG_COMMIT",
        "ST_P_BUILD_COMMIT",
        "ST_P_SYM_COMMIT",
        "ST_S_SYM_COMMIT",
        "ST_SELF_REDUCE_COMMIT",
        "ST_EKF_S_COPY_COMMIT",
        "ST_POST_SYM_COMMIT",
        "ST_DET_WAIT",
    ):
        require(core, rf"\b{state}\b", state, errors)

    # A raw global element index may select an operand at issue time, but it
    # must not remain the architectural destination selector.
    for bank in ("cov_predict", "measurement_cov", "sign_cov"):
        if re.search(rf"{bank}\s*\[\s*element_index\s*\]\s*<=", core):
            errors.append(f"raw element_index still writes {bank}")

    if "determinant <= pipe_rounded_mac" in core:
        errors.append("raw rounded MAC still writes determinant directly")

    overflow_capture = re.search(
        r"if\s*\(\s*cov_predict_mac_valid\s*\)\s*begin\s*"
        r"if\s*\(\s*EKF_MODE\s*!=\s*0\s*\)\s*begin"
        r"(?P<ekf_body>.*?)"
        r"end\s+else\s+if\s*\(\s*overflow50\s*\(\s*"
        r"cov_predict_mac_accumulator_reg\s*\)\s*\)\s*begin"
        r"(?P<bkf_body>.*?)end\s*end",
        core,
        flags=re.S,
    )
    if overflow_capture is None:
        errors.append(
            "missing structure: EKF registered overflow capture with BKF/rBKF direct branch"
        )
    else:
        ekf_body = overflow_capture.group("ekf_body")
        bkf_body = overflow_capture.group("bkf_body")
        require(
            ekf_body,
            r"cov_predict_overflow_local_reg\s*<=\s*overflow50\s*\(\s*"
            r"cov_predict_mac_accumulator_reg\s*\)",
            "EKF accumulator overflow captured into local register",
            errors,
        )
        require(
            ekf_body,
            r"cov_predict_overflow_local_valid_reg\s*<=\s*1'b1",
            "EKF local overflow valid capture",
            errors,
        )
        if "overflow_flag" in ekf_body:
            errors.append("EKF raw accumulator branch still writes overflow_flag directly")
        require(
            bkf_body,
            r"overflow_flag\s*<=\s*1'b1",
            "BKF/rBKF direct covariance overflow update",
            errors,
        )

    raw_cov_overflow_calls = re.findall(
        r"overflow50\s*\(\s*cov_predict_mac_accumulator_reg\s*\)", core
    )
    if len(raw_cov_overflow_calls) != 2:
        errors.append(
            "covariance accumulator overflow50 must appear only in the EKF capture "
            "and preserved BKF/rBKF direct branch"
        )
    require(
        core,
        r"if\s*\(\s*cov_predict_overflow_local_valid_reg\s*&&\s*"
        r"cov_predict_overflow_local_reg\s*\)\s*"
        r"overflow_flag\s*<=\s*1'b1",
        "global overflow update from registered EKF candidate",
        errors,
    )
    if re.search(
        r"overflow_flag\s*<=\s*overflow50\s*\(\s*"
        r"cov_predict_mac_accumulator_reg\s*\)",
        core,
    ):
        errors.append("raw covariance accumulator still directly assigns overflow_flag")

    for signal in (
        "capture_accumulator_reg",
        "raw_determinant_reg",
        "floor_determinant_reg",
        "floor_near_zero_reg",
        "result_solver_error_reg",
    ):
        require(determinant, rf"\b{signal}\b", f"determinant {signal}", errors)
    require(
        determinant,
        r"raw_determinant_reg\s*<=\s*round_sat50\(capture_accumulator_reg\)",
        "registered determinant rounding",
        errors,
    )
    require(
        determinant,
        r"result_solver_error_reg\s*<=\s*floor_near_zero_reg",
        "solver-error stage after registered floor metadata",
        errors,
    )
    require(
        ekf_test,
        r"dut\.u_engine\.f_matrix\s*\[\s*matrix_check_index\s*\]",
        "EKF registered transition coefficient comparison",
        errors,
    )
    require(
        ekf_test,
        r"dut\.u_engine\.matrix_temp\s*\[\s*matrix_check_index\s*\]",
        "EKF covariance-inner comparison",
        errors,
    )
    require(
        ekf_test,
        r"function\s+automatic\s+overflow50_reference",
        "EKF independent overflow50 assertion reference",
        errors,
    )
    require(
        ekf_test,
        r"cov_predict_overflow_local_valid_reg\s*!==\s*"
        r"cov_predict_mac_valid_d",
        "EKF local overflow valid alignment assertion",
        errors,
    )
    require(
        ekf_test,
        r"overflow50_reference\s*\(\s*cov_predict_mac_accumulator_d\s*\)",
        "EKF local overflow candidate value assertion",
        errors,
    )
    require(
        ekf_test,
        r"result_valid\s*\|\|\s*done.*?"
        r"cov_predict_overflow_local_valid_reg",
        "EKF result/done overflow pipeline drain assertion",
        errors,
    )
    require(
        equivalence_test,
        r"f_matrix_hex,cov_inner_hex,cov_predict_hex",
        "pre/post transition and covariance-inner trace fields",
        errors,
    )

    # Historical byte equality is incompatible with the required width edits.
    # Assert the existing register boundaries/handshake and iteration formula;
    # the independent unit tests exercise latency and stall behavior, and the
    # generalized W=24/F=16 regression checks against the latest source.
    multiply = (ROOT / "rtl/common/fx_mul_mac_pipeline.v").read_text(encoding="utf-8")
    divider = (ROOT / "rtl/common/fx_divider_q8_16.v").read_text(encoding="utf-8")
    for pattern, description in (
        (r"stage1_operand_a\s*<=\s*request_operand_a", "MAC input operand register"),
        (r"stage1_accumulator\s*<=\s*request_accumulator", "MAC input accumulator register"),
        (r"stage2_product\s*<=\s*stage1_product", "MAC full product register"),
        (r"stage2_accumulator\s*<=\s*stage1_accumulator", "MAC aligned accumulator register"),
        (r"stage3_rounded_product\s*<=\s*round_sat48\(stage2_product\)", "MAC rounded product register"),
        (r"stage3_mac_sum\s*<=\s*stage2_mac_sum", "MAC final sum register"),
        (r"assign\s+request_ready\s*=\s*!stage1_valid_reg\s*&&\s*!stage2_valid_reg\s*&&\s*!stage3_valid_reg", "MAC shared resource ready policy"),
        (r"if\s*\(stage3_valid_reg\s*&&\s*result_ready\)", "MAC output ready handshake"),
        (r"assign\s+result_valid\s*=\s*stage3_valid_reg", "MAC stage-three valid"),
    ):
        require(multiply, pattern, description, errors)
    for pattern, description in (
        (r"MAGNITUDE_WIDTH\s*=\s*DATA_WIDTH\s*\+\s*1", "divider extended absolute magnitude"),
        (r"DIVIDEND_WIDTH\s*=\s*MAGNITUDE_WIDTH\s*\+\s*FRACTION_WIDTH", "divider scaled dividend width"),
        (r"ITERATION_COUNT\s*=\s*DIVIDEND_WIDTH", "divider unchanged W+1+F iteration formula"),
        (r"divisor_stage_a\s*<=\s*divisor_input_reg", "divider input-to-stage-A register"),
        (r"remainder_stage_b\s*<=\s*remainder_after_iteration", "divider stage-B remainder register"),
        (r"quotient_stage_b\s*<=\s*quotient_after_iteration", "divider stage-B quotient register"),
        (r"if\s*\(start\s*&&\s*!busy\)", "divider transaction acceptance"),
        (r"if\s*\(stage_b_valid\)\s*begin\s*stage_b_valid\s*<=\s*1'b0;\s*busy\s*<=\s*1'b0;\s*valid\s*<=\s*1'b1", "divider result commit stage"),
    ):
        require(divider, pattern, description, errors)

    xdc_path = ROOT / "constraints" / "common_clock.xdc"
    xdc = xdc_path.read_text(encoding="utf-8")
    active_xdc = strip_tcl_comments(xdc)
    require(
        active_xdc,
        r"(?m)^\s*create_clock\s+-name\s+estimator_clk\s+"
        r"-period\s+10\.000\s+\[get_ports\s+clk\]\s*$",
        "single exact 10.000 ns estimator clock",
        errors,
    )
    if len(re.findall(r"(?im)^\s*create_clock\b", active_xdc)) != 1:
        errors.append("common_clock.xdc must contain exactly one active create_clock")
    timing_exception_patterns = (
        r"\bset_multicycle_path\b",
        r"\bset_false_path\b",
        r"\bset_clock_uncertainty\b",
        r"\bset_case_analysis\b",
        r"\bset_max_delay\b",
        r"\bset_min_delay\b",
        r"\bset_disable_timing\b",
        r"\bset_clock_groups\b",
        r"\bset_clock_latency\b",
    )
    for pattern in timing_exception_patterns:
        if re.search(pattern, active_xdc, flags=re.I):
            errors.append(f"forbidden XDC timing override: {pattern}")

    tcl = (ROOT / "scripts" / "vivado" / "run_all.tcl").read_text(encoding="utf-8")
    active_tcl = strip_tcl_comments(tcl)
    for pattern in timing_exception_patterns + (r"\bcreate_clock\b",):
        if re.search(pattern, active_tcl, flags=re.I):
            errors.append(f"forbidden Tcl timing override: {pattern}")
    implementation_override_patterns = (
        r"\bPerformance_[A-Za-z0-9_]+\b",
        r"\bset_property\s+strategy\b",
        r"\bset_property\s+steps\.[^\s]+\.args\.directive\b",
        r"\b(?:synth_design|opt_design|power_opt_design|place_design|"
        r"phys_opt_design|route_design)\b[^\n;]*\s-directive\b",
        r"\b(?:set_property|set_param)\b[^\n;]*\bseed\b",
        r"\b(?:create_run|launch_runs)\b[^\n;]*\s-strategy\b",
    )
    for pattern in implementation_override_patterns:
        if re.search(pattern, active_tcl, flags=re.I):
            errors.append(f"forbidden implementation override: {pattern}")
    require(active_tcl, r"\bphys_opt_design\b", "existing phys_opt_design step", errors)

    if errors:
        raise SystemExit("\n".join(errors))
    print("PASS: WNS/common pipeline register boundaries, divider iteration formula, and timing constraints")


if __name__ == "__main__":
    main()
