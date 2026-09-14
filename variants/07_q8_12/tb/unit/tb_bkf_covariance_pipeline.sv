`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

module tb_bkf_covariance_pipeline;
    `include "tb/unit/fx_format_tb.vh"
    localparam signed [W-1:0] FX_ONE = fx_q16(64'sd65536);
    localparam signed [W-1:0] FX_MAX = TB_MAX_WORD;
    localparam signed [W-1:0] FX_MIN = TB_MIN_WORD;

    reg clk;
    reg rst_n;
    reg cfg_valid;
    wire cfg_ready;
    reg [3*W-1:0] cfg_state_flat;
    reg [9*W-1:0] cfg_cov_flat;
    reg model_valid;
    wire model_ready;
    reg [9*W-1:0] f_input_flat;
    wire threshold_valid;
    reg threshold_ready;
    wire [3*W-1:0] threshold_flat;
    reg observation_valid;
    wire observation_ready;
    reg [2:0] observation_flat;
    reg [3*W-1:0] measurement_flat;
    wire result_valid;
    reg result_ready;
    wire [3*W-1:0] state_out_flat;
    wire [9*W-1:0] cov_out_flat;
    wire busy;
    wire done;
    wire overflow_flag;
    wire numeric_error;
    wire solver_error;
    wire [5:0] fsm_state;
    wire [9*W-1:0] debug_cov_predict_flat;
    wire [9*W-1:0] debug_sign_cov_flat;
    wire [9*W-1:0] debug_gain_flat;
    wire signed [W-1:0] debug_determinant;
    wire [3*W-1:0] debug_reduced_observation_flat;
    wire [47:0] debug_branch_sum_flat;

    integer cycle_count;
    integer case_count;
    integer reference_latency;
    integer ghost_result_count;

    bkf_core #(
        .NUM_BRANCHES(1),
        .EKF_MODE(0)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_valid(cfg_valid),
        .cfg_ready(cfg_ready),
        .cfg_state_flat(cfg_state_flat),
        .cfg_cov_flat(cfg_cov_flat),
        .model_valid(model_valid),
        .model_ready(model_ready),
        .f_input_flat(f_input_flat),
        .threshold_valid(threshold_valid),
        .threshold_ready(threshold_ready),
        .threshold_flat(threshold_flat),
        .observation_valid(observation_valid),
        .observation_ready(observation_ready),
        .observation_flat(observation_flat),
        .measurement_flat(measurement_flat),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .state_out_flat(state_out_flat),
        .cov_out_flat(cov_out_flat),
        .busy(busy),
        .done(done),
        .overflow_flag(overflow_flag),
        .numeric_error(numeric_error),
        .solver_error(solver_error),
        .fsm_state(fsm_state),
        .debug_cov_predict_flat(debug_cov_predict_flat),
        .debug_sign_cov_flat(debug_sign_cov_flat),
        .debug_gain_flat(debug_gain_flat),
        .debug_determinant(debug_determinant),
        .debug_reduced_observation_flat(debug_reduced_observation_flat),
        .debug_branch_sum_flat(debug_branch_sum_flat)
    );

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            ghost_result_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (result_valid || done)
                ghost_result_count <= ghost_result_count + 1;
            if (threshold_valid &&
                ((^threshold_flat === 1'bx) ||
                 (^debug_cov_predict_flat === 1'bx))) begin
                $display("FAIL: prediction output contains X/Z while threshold_valid");
                $fatal(1);
            end
        end
    end

    function automatic [3*W-1:0] pack_vector3;
        input signed [W-1:0] value0;
        input signed [W-1:0] value1;
        input signed [W-1:0] value2;
        begin
            pack_vector3 = {value2, value1, value0};
        end
    endfunction

    function automatic [9*W-1:0] pack_matrix3;
        input signed [W-1:0] value0;
        input signed [W-1:0] value1;
        input signed [W-1:0] value2;
        input signed [W-1:0] value3;
        input signed [W-1:0] value4;
        input signed [W-1:0] value5;
        input signed [W-1:0] value6;
        input signed [W-1:0] value7;
        input signed [W-1:0] value8;
        begin
            pack_matrix3 = {value8, value7, value6, value5, value4,
                            value3, value2, value1, value0};
        end
    endfunction

    task automatic fail;
        input [8*96-1:0] message;
        begin
            $display("FAIL: %0s cycle=%0d state=%0d", message,
                     cycle_count, fsm_state);
            $fatal(1);
        end
    endtask

    task automatic check_all_pipeline_valids_clear;
        input [8*48-1:0] context_name;
        begin
            if (dut.cov_predict_mac_valid ||
                dut.add_q_operand_valid ||
                dut.cov_sym_operand_valid ||
                dut.measurement_operand_valid ||
                dut.measurement_sym_operand_valid ||
                dut.sign_sym_operand_valid ||
                dut.self_reduce_operand_valid ||
                dut.ekf_sign_copy_valid ||
                dut.post_sym_operand_valid ||
                dut.branch_reduction_valid ||
                dut.pipeline_stage1_valid ||
                dut.pipeline_stage2_valid ||
                dut.pipeline_stage3_valid ||
                dut.pipe_result_valid ||
                dut.det_finalize_request_valid ||
                dut.det_capture_stage_valid ||
                dut.det_round_stage_valid ||
                dut.det_floor_stage_valid ||
                dut.det_finalize_valid ||
                dut.divider_valid) begin
                $display("FAIL: context=%0s local/determinant valid remained asserted",
                         context_name);
                $fatal(1);
            end
        end
    endtask

    task automatic reset_core;
        begin
            cfg_valid = 1'b0;
            model_valid = 1'b0;
            threshold_ready = 1'b0;
            observation_valid = 1'b0;
            result_ready = 1'b0;
            rst_n = 1'b0;
            repeat (3) @(negedge clk);
            #1;
            check_all_pipeline_valids_clear("reset_core");
            if (threshold_valid || result_valid || done || busy)
                fail("external valid/busy asserted during reset");
            rst_n = 1'b1;
            repeat (2) @(negedge clk);
            if (!cfg_ready || busy || threshold_valid || result_valid || done)
                fail("core did not return to unconfigured idle after reset");
        end
    endtask

    task automatic configure_and_start;
        input [3*W-1:0] initial_state;
        input [9*W-1:0] initial_covariance;
        input [9*W-1:0] transition_matrix;
        output integer accept_cycle;
        begin
            while (!cfg_ready) @(negedge clk);
            cfg_state_flat = initial_state;
            cfg_cov_flat = initial_covariance;
            cfg_valid = 1'b1;
            @(negedge clk);
            cfg_valid = 1'b0;

            while (!model_ready) @(negedge clk);
            f_input_flat = transition_matrix;
            measurement_flat = {3*W{1'b0}};
            model_valid = 1'b1;
            @(negedge clk);
            model_valid = 1'b0;
            accept_cycle = cycle_count;
        end
    endtask

    task automatic compare_vector;
        input [3*W-1:0] actual;
        input [3*W-1:0] expected;
        input [8*48-1:0] case_name;
        integer element;
        begin
            for (element = 0; element < 3; element = element + 1) begin
                if ($signed(actual[(element*W) +: W]) !==
                    $signed(expected[(element*W) +: W])) begin
                    $display("FAIL: case=%0s state element=%0d expected=%0d actual=%0d",
                             case_name, element,
                             $signed(expected[(element*W) +: W]),
                             $signed(actual[(element*W) +: W]));
                    $fatal(1);
                end
            end
        end
    endtask

    task automatic compare_matrix;
        input [9*W-1:0] actual;
        input [9*W-1:0] expected;
        input [8*48-1:0] case_name;
        integer element;
        begin
            for (element = 0; element < 9; element = element + 1) begin
                if ($signed(actual[(element*W) +: W]) !==
                    $signed(expected[(element*W) +: W])) begin
                    $display("FAIL: case=%0s covariance element=%0d expected=%0d actual=%0d",
                             case_name, element,
                             $signed(expected[(element*W) +: W]),
                             $signed(actual[(element*W) +: W]));
                    $fatal(1);
                end
            end
        end
    endtask

    task automatic run_prediction_case;
        input [8*48-1:0] case_name;
        input [3*W-1:0] initial_state;
        input [9*W-1:0] initial_covariance;
        input [9*W-1:0] transition_matrix;
        input [9*W-1:0] expected_cov_inner;
        input [3*W-1:0] expected_state_predict;
        input [9*W-1:0] expected_cov_predict;
        input expected_overflow;
        integer accept_cycle;
        integer observed_latency;
        integer matrix_element;
        begin
            reset_core();
            configure_and_start(initial_state, initial_covariance,
                                transition_matrix, accept_cycle);

            while (!threshold_valid) @(negedge clk);
            observed_latency = cycle_count - accept_cycle;
            if (reference_latency < 0)
                reference_latency = observed_latency;
            else if (observed_latency != reference_latency)
                fail("prediction latency varied across directed cases");

            for (matrix_element = 0; matrix_element < 9;
                 matrix_element = matrix_element + 1) begin
                if ($signed(dut.f_matrix[matrix_element]) !==
                    $signed(transition_matrix[(matrix_element*W) +: W]))
                    fail("registered transition coefficient mismatch");
                if ($signed(dut.matrix_temp[matrix_element]) !==
                    $signed(expected_cov_inner[(matrix_element*W) +: W]))
                    fail("covariance inner intermediate mismatch");
            end
            compare_vector(threshold_flat, expected_state_predict, case_name);
            compare_matrix(debug_cov_predict_flat, expected_cov_predict, case_name);
            if (overflow_flag !== expected_overflow) begin
                $display("FAIL: case=%0s overflow expected=%b actual=%b",
                         case_name, expected_overflow, overflow_flag);
                $fatal(1);
            end
            if (numeric_error || solver_error || result_valid || done || !busy)
                fail("unexpected status at prediction threshold");
            check_all_pipeline_valids_clear("threshold boundary");
            case_count = case_count + 1;
        end
    endtask

    task automatic test_mid_operation_reset_flush;
        integer accept_cycle;
        integer wait_cycles;
        integer results_before_reset;
        begin
            reset_core();
            threshold_ready = 1'b1;
            result_ready = 1'b1;
            configure_and_start(
                pack_vector3(0, 0, 0),
                pack_matrix3(FX_ONE, 0, 0,
                             0, FX_ONE, 0,
                             0, 0, FX_ONE),
                pack_matrix3(FX_ONE, 0, 0,
                             0, FX_ONE, 0,
                             0, 0, FX_ONE),
                accept_cycle);

            wait_cycles = 0;
            while (!threshold_valid && (wait_cycles < 2000)) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!threshold_valid)
                fail("reset case did not reach threshold");

            while (!observation_ready) @(negedge clk);
            observation_flat = 3'b101;
            observation_valid = 1'b1;
            @(negedge clk);
            observation_valid = 1'b0;

            wait_cycles = 0;
            while (!dut.det_round_stage_valid && (wait_cycles < 4000)) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!dut.det_round_stage_valid)
                fail("reset case did not reach determinant round stage");

            results_before_reset = ghost_result_count;
            rst_n = 1'b0;
            #1;
            check_all_pipeline_valids_clear("mid-operation reset");
            if (threshold_valid || result_valid || done || busy ||
                (state_out_flat !== {3*W{1'b0}}) || (cov_out_flat !== {9*W{1'b0}}) ||
                (debug_cov_predict_flat !== {9*W{1'b0}}))
                fail("mid-operation reset did not clear visible state/valids");

            cfg_valid = 1'b0;
            model_valid = 1'b0;
            threshold_ready = 1'b0;
            observation_valid = 1'b0;
            result_ready = 1'b1;
            repeat (2) @(negedge clk);
            rst_n = 1'b1;

            for (wait_cycles = 0; wait_cycles < 200; wait_cycles = wait_cycles + 1) begin
                @(negedge clk);
                check_all_pipeline_valids_clear("post-reset ghost window");
                if (threshold_valid || result_valid || done || busy)
                    fail("ghost completion after mid-operation reset");
            end
            if (ghost_result_count != results_before_reset)
                fail("result/done accounting changed after aborted transaction");
            if (!cfg_ready || dut.configured)
                fail("configuration was not flushed by mid-operation reset");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cfg_valid = 1'b0;
        cfg_state_flat = {3*W{1'b0}};
        cfg_cov_flat = {9*W{1'b0}};
        model_valid = 1'b0;
        f_input_flat = {9*W{1'b0}};
        threshold_ready = 1'b0;
        observation_valid = 1'b0;
        observation_flat = 3'd0;
        measurement_flat = {3*W{1'b0}};
        result_ready = 1'b0;
        cycle_count = 0;
        case_count = 0;
        reference_latency = -1;
        ghost_result_count = 0;

        // Zero state/covariance with identity F: only Q_DIAG is added.
        run_prediction_case(
            "zero_identity",
            pack_vector3(0, 0, 0),
            pack_matrix3(0, 0, 0,
                         0, 0, 0,
                         0, 0, 0),
            pack_matrix3(FX_ONE, 0, 0,
                         0, FX_ONE, 0,
                         0, 0, FX_ONE),
            pack_matrix3(0, 0, 0,
                         0, 0, 0,
                         0, 0, 0),
            pack_vector3(0, 0, 0),
            pack_matrix3(`FX_Q8_16_Q_DIAG, 0, 0,
                         0, `FX_Q8_16_Q_DIAG, 0,
                         0, 0, `FX_Q8_16_Q_DIAG),
            1'b0);

        // Identity F preserves mixed signed, symmetric off-diagonal elements.
        run_prediction_case(
            "mixed_signed_covariance",
            pack_vector3(fx_q16(64'sd65536), -fx_q16(64'sd131072), fx_q16(64'sd32768)),
            pack_matrix3(fx_q16(64'sd65536), fx_q16(64'sd16384), -fx_q16(64'sd32768),
                         fx_q16(64'sd16384), fx_q16(64'sd131072), fx_q16(64'sd8192),
                         -fx_q16(64'sd32768), fx_q16(64'sd8192), fx_q16(64'sd196608)),
            pack_matrix3(FX_ONE, 0, 0,
                         0, FX_ONE, 0,
                         0, 0, FX_ONE),
            pack_matrix3(fx_q16(64'sd65536), fx_q16(64'sd16384), -fx_q16(64'sd32768),
                         fx_q16(64'sd16384), fx_q16(64'sd131072), fx_q16(64'sd8192),
                         -fx_q16(64'sd32768), fx_q16(64'sd8192), fx_q16(64'sd196608)),
            pack_vector3(fx_q16(64'sd65536), -fx_q16(64'sd131072), fx_q16(64'sd32768)),
            pack_matrix3((fx_q16(64'sd65536) + `FX_Q8_16_Q_DIAG), fx_q16(64'sd16384), -fx_q16(64'sd32768),
                         fx_q16(64'sd16384), (fx_q16(64'sd131072) + `FX_Q8_16_Q_DIAG), fx_q16(64'sd8192),
                         -fx_q16(64'sd32768), fx_q16(64'sd8192), (fx_q16(64'sd196608) + `FX_Q8_16_Q_DIAG)),
            1'b0);

        // Unsymmetric one-LSB pairs exercise positive and negative ties away
        // from zero at the covariance symmetry boundary.
        run_prediction_case(
            "symmetry_half_away",
            pack_vector3(0, 0, 0),
            pack_matrix3(fx_q16(64'sd65536), 0, 0,
                         1, fx_q16(64'sd65536), 2,
                         -1, 3, fx_q16(64'sd65536)),
            pack_matrix3(FX_ONE, 0, 0,
                         0, FX_ONE, 0,
                         0, 0, FX_ONE),
            pack_matrix3(fx_q16(64'sd65536), 0, 0,
                         1, fx_q16(64'sd65536), 2,
                         -1, 3, fx_q16(64'sd65536)),
            pack_vector3(0, 0, 0),
            pack_matrix3((fx_q16(64'sd65536) + `FX_Q8_16_Q_DIAG), 1, -1,
                         1, (fx_q16(64'sd65536) + `FX_Q8_16_Q_DIAG), 3,
                         -1, 3, (fx_q16(64'sd65536) + `FX_Q8_16_Q_DIAG)),
            1'b0);

        // Adding Q_DIAG to an exact maximum diagonal must saturate and flag.
        run_prediction_case(
            "maximum_diagonal_saturation",
            pack_vector3(FX_MAX, FX_MIN, 0),
            pack_matrix3(FX_MAX, 0, 0,
                         0, FX_MAX, 0,
                         0, 0, FX_MAX),
            pack_matrix3(FX_ONE, 0, 0,
                         0, FX_ONE, 0,
                         0, 0, FX_ONE),
            pack_matrix3(FX_MAX, 0, 0,
                         0, FX_MAX, 0,
                         0, 0, FX_MAX),
            pack_vector3(FX_MAX, FX_MIN, 0),
            pack_matrix3(FX_MAX, 0, 0,
                         0, FX_MAX, 0,
                         0, 0, FX_MAX),
            1'b1);

        // Nontrivial F*P*F^T case with positive/negative mixing.
        run_prediction_case(
            "nontrivial_fixed_matrix",
            pack_vector3(fx_q16(64'sd65536), -fx_q16(64'sd131072), fx_q16(64'sd32768)),
            pack_matrix3(fx_q16(64'sd65536), 0, 0,
                         0, fx_q16(64'sd131072), 0,
                         0, 0, fx_q16(64'sd32768)),
            pack_matrix3(fx_q16(64'sd65536), fx_q16(64'sd32768), 0,
                         -fx_q16(64'sd16384), fx_q16(64'sd65536), 0,
                         0, 0, fx_q16(64'sd65536)),
            pack_matrix3(fx_q16(64'sd65536), -fx_q16(64'sd16384), 0,
                         fx_q16(64'sd65536), fx_q16(64'sd131072), 0,
                         0, 0, fx_q16(64'sd32768)),
            pack_vector3(0, -fx_q16(64'sd147456), fx_q16(64'sd32768)),
            pack_matrix3((fx_q16(64'sd98304) + `FX_Q8_16_Q_DIAG), fx_q16(64'sd49152), 0,
                         fx_q16(64'sd49152), (fx_q16(64'sd135168) + `FX_Q8_16_Q_DIAG), 0,
                         0, 0, (fx_q16(64'sd32768) + `FX_Q8_16_Q_DIAG)),
            1'b0);

        test_mid_operation_reset_flush();

        if (case_count != 5)
            fail("directed prediction case count mismatch");
        $display("PASS: bkf covariance pipeline directed=%0d reset_flush=1 mismatch=0 threshold_latency=%0d",
                 case_count, reference_latency);
        $finish;
    end

    initial begin
        #10000000;
        $display("FAIL: bkf covariance pipeline timeout state=%0d", fsm_state);
        $fatal(1);
    end
endmodule

`default_nettype wire
