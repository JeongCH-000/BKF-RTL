`timescale 1ns/1ps
`default_nettype none

module tb_bkf_full;
    localparam integer MAX_STEPS = 500;
    localparam integer CLK_PERIOD_NS = 10;

    reg clk;
    reg rst_n;
    reg cfg_valid;
    wire cfg_ready;
    reg [71:0] cfg_state_flat;
    reg [215:0] cfg_cov_flat;
    reg model_valid;
    wire model_ready;
    reg [215:0] f_input_flat;
    wire threshold_valid;
    reg threshold_ready;
    wire [71:0] threshold_flat;
    reg observation_valid;
    wire observation_ready;
    reg [2:0] observation_flat;
    wire result_valid;
    reg result_ready;
    wire [71:0] state_out_flat;
    wire [215:0] cov_out_flat;
    wire busy;
    wire done;
    wire overflow_flag;
    wire numeric_error;
    wire solver_error;
    wire [5:0] fsm_state;
    wire [215:0] debug_cov_predict_flat;
    wire [215:0] debug_sign_cov_flat;
    wire [215:0] debug_gain_flat;
    wire signed [23:0] debug_determinant;

    reg [71:0] init_state_mem [0:0];
    reg [215:0] init_cov_mem [0:0];
    reg [215:0] f_mem [0:MAX_STEPS-1];
    reg [71:0] measurement_mem [0:MAX_STEPS-1];
    reg [71:0] threshold_expected_mem [0:MAX_STEPS-1];
    reg [2:0] observation_expected_mem [0:MAX_STEPS-1];
    reg [71:0] state_expected_mem [0:MAX_STEPS-1];
    reg [215:0] cov_expected_mem [0:MAX_STEPS-1];
    reg [215:0] cov_predict_expected_mem [0:MAX_STEPS-1];
    reg [215:0] sign_cov_expected_mem [0:MAX_STEPS-1];
    reg [215:0] gain_expected_mem [0:MAX_STEPS-1];
    reg [23:0] determinant_expected_mem [0:MAX_STEPS-1];

    integer cycle_count;
    integer sample_start_cycle;
    integer step;
    integer requested_steps;
    integer rtl_file;
    integer mismatch_file;
    integer cycle_file;
    integer accepted_count;
    integer completion_count;
    integer measured_latency;
    integer channel;
    integer matrix_element;
    reg [2:0] generated_observation;

    reg signed [23:0] measurement_element;
    reg signed [23:0] threshold_element;

`ifdef WNS_CLOSURE_ASSERTIONS
    reg det_capture_valid_d;
    reg det_round_valid_d;
    reg det_floor_valid_d;
    reg det_result_valid_d;

    function automatic valid_symmetric_mask;
        input [8:0] mask;
        begin
            valid_symmetric_mask = (mask == 9'b000001010) ||
                                   (mask == 9'b001000100) ||
                                   (mask == 9'b010100000);
        end
    endfunction

    function automatic valid_onehot9;
        input [8:0] value;
        begin
            valid_onehot9 = (value != 9'd0) &&
                            ((value & (value - 9'd1)) == 9'd0);
        end
    endfunction

    function automatic valid_zero_or_onehot9;
        input [8:0] value;
        begin
            valid_zero_or_onehot9 = (value == 9'd0) || valid_onehot9(value);
        end
    endfunction

    function automatic valid_zero_or_onehot4;
        input [3:0] value;
        begin
            valid_zero_or_onehot4 = (value == 4'd0) ||
                                    ((value & (value - 4'd1)) == 4'd0);
        end
    endfunction
`endif

    bkf_core dut (
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
        .measurement_flat(72'd0),
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
        .debug_determinant(debug_determinant)
    );

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            accepted_count <= 0;
            completion_count <= 0;
            if (dut.pipeline_stage1_valid || dut.pipeline_stage2_valid ||
                dut.pipeline_stage3_valid || result_valid || done) begin
                $display("FAIL: BKF pipeline valid/done asserted during reset");
                $fatal(1);
            end
`ifdef WNS_CLOSURE_ASSERTIONS
            det_capture_valid_d <= 1'b0;
            det_round_valid_d <= 1'b0;
            det_floor_valid_d <= 1'b0;
            det_result_valid_d <= 1'b0;
            if (dut.cov_predict_mac_valid || dut.add_q_operand_valid ||
                dut.cov_sym_operand_valid || dut.measurement_operand_valid ||
                dut.measurement_sym_operand_valid || dut.sign_sym_operand_valid ||
                dut.self_reduce_operand_valid || dut.ekf_sign_copy_valid ||
                dut.post_sym_operand_valid || dut.branch_reduction_valid ||
                dut.det_capture_stage_valid || dut.det_round_stage_valid ||
                dut.det_floor_stage_valid || dut.det_finalize_valid) begin
                $display("FAIL: BKF WNS-closure valid asserted during reset");
                $fatal(1);
            end
`endif
        end else begin
            cycle_count <= cycle_count + 1;
            if (model_valid && model_ready) accepted_count <= accepted_count + 1;
            if (result_valid && result_ready) completion_count <= completion_count + 1;
            if ((dut.pipeline_stage1_valid && dut.pipeline_stage2_valid) ||
                (dut.pipeline_stage1_valid && dut.pipeline_stage3_valid) ||
                (dut.pipeline_stage2_valid && dut.pipeline_stage3_valid)) begin
                $display("FAIL: BKF arithmetic pipeline stages overlap unexpectedly");
                $fatal(1);
            end
            if (dut.pipeline_stage1_valid &&
                ((dut.u_mul_mac_pipeline.stage1_operation !== dut.state) ||
                 (dut.u_mul_mac_pipeline.stage1_element_index !== dut.element_index) ||
                 (dut.u_mul_mac_pipeline.stage1_row_index !== dut.row_index) ||
                 (dut.u_mul_mac_pipeline.stage1_col_index !== dut.col_index) ||
                 (dut.u_mul_mac_pipeline.stage1_dot_index !== dut.dot_index))) begin
                $display("FAIL: BKF stage1 metadata is not synchronized");
                $fatal(1);
            end
            if (dut.pipeline_stage2_valid &&
                (dut.u_mul_mac_pipeline.stage2_operation !== dut.state)) begin
                $display("FAIL: BKF stage2 operation metadata is not synchronized");
                $fatal(1);
            end
            if (dut.pipeline_stage3_valid &&
                ((dut.pipe_result_operation !== dut.state) ||
                 (dut.pipe_result_element_index !== dut.element_index) ||
                 (dut.pipe_result_row_index !== dut.row_index) ||
                 (dut.pipe_result_col_index !== dut.col_index) ||
                 (dut.pipe_result_dot_index !== dut.dot_index))) begin
                $display("FAIL: BKF stage3 metadata is not synchronized");
                $fatal(1);
            end
            if (result_valid && ((^state_out_flat === 1'bx) || (^cov_out_flat === 1'bx))) begin
                $display("FAIL: BKF output contains X/Z while valid");
                $fatal(1);
            end
`ifdef WNS_CLOSURE_ASSERTIONS
            if ((^{dut.cov_predict_mac_valid, dut.add_q_operand_valid,
                   dut.cov_sym_operand_valid, dut.measurement_operand_valid,
                   dut.measurement_sym_operand_valid, dut.sign_sym_operand_valid,
                   dut.self_reduce_operand_valid, dut.ekf_sign_copy_valid,
                   dut.post_sym_operand_valid} === 1'bx) ||
                !valid_zero_or_onehot9({dut.cov_predict_mac_valid, dut.add_q_operand_valid,
                           dut.cov_sym_operand_valid, dut.measurement_operand_valid,
                           dut.measurement_sym_operand_valid, dut.sign_sym_operand_valid,
                           dut.self_reduce_operand_valid, dut.ekf_sign_copy_valid,
                           dut.post_sym_operand_valid})) begin
                $display("FAIL: BKF local writeback valids overlap or contain X/Z");
                $fatal(1);
            end
            if (dut.cov_predict_mac_valid &&
                ((dut.state !== dut.ST_COV_OUTER_COMMIT) ||
                 !valid_onehot9(dut.cov_predict_mac_write_mask_reg) ||
                 (dut.cov_predict_mac_write_mask_reg[
                    (dut.cov_predict_mac_row_reg*3)+dut.cov_predict_mac_col_reg] !== 1'b1) ||
                 (dut.cov_predict_mac_last_reg !==
                    ((dut.cov_predict_mac_row_reg == 2'd2) &&
                     (dut.cov_predict_mac_col_reg == 2'd2))))) begin
                $display("FAIL: BKF cov_predict writeback data/metadata mismatch");
                $fatal(1);
            end
            if (dut.add_q_operand_valid &&
                ((dut.state !== dut.ST_ADD_Q_COMMIT) ||
                 !valid_onehot9(dut.add_q_write_mask_reg) ||
                 (dut.add_q_last_reg !== dut.add_q_write_mask_reg[8]))) begin
                $display("FAIL: BKF add-Q writeback data/metadata mismatch");
                $fatal(1);
            end
            if (dut.cov_sym_operand_valid &&
                ((dut.state !== dut.ST_SYM_SIG_COMMIT) ||
                 !valid_symmetric_mask(dut.cov_sym_write_mask_reg) ||
                 (dut.cov_sym_last_reg !==
                    (dut.cov_sym_write_mask_reg == 9'b010100000)))) begin
                $display("FAIL: BKF covariance symmetry data/metadata mismatch");
                $fatal(1);
            end
            if (dut.measurement_operand_valid &&
                ((dut.state !== dut.ST_P_BUILD_COMMIT) ||
                 !valid_onehot9(dut.measurement_write_mask_reg) ||
                 (dut.measurement_last_reg !== dut.measurement_write_mask_reg[8]))) begin
                $display("FAIL: BKF measurement writeback data/metadata mismatch");
                $fatal(1);
            end
            if (dut.measurement_sym_operand_valid &&
                ((dut.state !== dut.ST_P_SYM_COMMIT) ||
                 !valid_symmetric_mask(dut.measurement_sym_write_mask_reg) ||
                 (dut.measurement_sym_last_reg !==
                    (dut.measurement_sym_write_mask_reg == 9'b010100000)))) begin
                $display("FAIL: BKF measurement symmetry data/metadata mismatch");
                $fatal(1);
            end
            if (dut.sign_sym_operand_valid &&
                ((dut.state !== dut.ST_S_SYM_COMMIT) ||
                 !valid_symmetric_mask(dut.sign_sym_write_mask_reg) ||
                 (dut.sign_sym_last_reg !==
                    (dut.sign_sym_write_mask_reg == 9'b010100000)))) begin
                $display("FAIL: BKF sign symmetry data/metadata mismatch");
                $fatal(1);
            end
            if (dut.self_reduce_operand_valid &&
                ((dut.state !== dut.ST_SELF_REDUCE_COMMIT) ||
                 !valid_onehot9(dut.self_reduce_write_mask_reg) ||
                 (|(dut.self_reduce_write_mask_reg & 9'b011101110)) ||
                 (dut.self_reduce_last_reg !== dut.self_reduce_write_mask_reg[8]))) begin
                $display("FAIL: BKF self-reduction data/metadata mismatch");
                $fatal(1);
            end
            if (dut.ekf_sign_copy_valid &&
                ((dut.state !== dut.ST_EKF_S_COPY_COMMIT) ||
                 !valid_onehot9(dut.ekf_sign_copy_write_mask_reg) ||
                 (dut.ekf_sign_copy_last_reg !== dut.ekf_sign_copy_write_mask_reg[8]))) begin
                $display("FAIL: BKF sign-copy data/metadata mismatch");
                $fatal(1);
            end
            if (dut.post_sym_operand_valid &&
                ((dut.state !== dut.ST_POST_SYM_COMMIT) ||
                 !valid_symmetric_mask(dut.post_sym_write_mask_reg) ||
                 (dut.post_sym_last_reg !==
                    (dut.post_sym_write_mask_reg == 9'b010100000)))) begin
                $display("FAIL: BKF posterior symmetry data/metadata mismatch");
                $fatal(1);
            end
            if ((^{dut.det_capture_stage_valid, dut.det_round_stage_valid,
                   dut.det_floor_stage_valid, dut.det_finalize_valid} === 1'bx) ||
                !valid_zero_or_onehot4({dut.det_capture_stage_valid, dut.det_round_stage_valid,
                           dut.det_floor_stage_valid, dut.det_finalize_valid}) ||
                ((dut.det_capture_stage_valid || dut.det_round_stage_valid ||
                  dut.det_floor_stage_valid || dut.det_finalize_valid) &&
                 (dut.state !== dut.ST_DET_WAIT))) begin
                $display("FAIL: BKF determinant stage valid/state mismatch");
                $fatal(1);
            end
            if ((dut.det_round_stage_valid && !det_round_valid_d && !det_capture_valid_d) ||
                (dut.det_floor_stage_valid && !det_floor_valid_d && !det_round_valid_d) ||
                (dut.det_finalize_valid && !det_result_valid_d && !det_floor_valid_d)) begin
                $display("FAIL: BKF determinant valid did not advance with its data");
                $fatal(1);
            end
            det_capture_valid_d <= dut.det_capture_stage_valid;
            det_round_valid_d <= dut.det_round_stage_valid;
            det_floor_valid_d <= dut.det_floor_stage_valid;
            det_result_valid_d <= dut.det_finalize_valid;
`endif
        end
    end

    task fail_mismatch;
        input integer fail_step;
        input [8*32-1:0] signal_name;
        input integer element;
        input signed [31:0] expected_value;
        input signed [31:0] actual_value;
        begin
            $fdisplay(mismatch_file, "%0d,%0s,%0d,%0d,%0d,%0d", fail_step, signal_name, element,
                      expected_value, actual_value, cycle_count);
            $display("FAIL: first mismatch step=%0d signal=%0s element=%0d expected=%0d actual=%0d cycle=%0d",
                     fail_step, signal_name, element, expected_value, actual_value, cycle_count);
            $fatal(1);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cfg_valid = 1'b0;
        cfg_state_flat = 72'd0;
        cfg_cov_flat = 216'd0;
        model_valid = 1'b0;
        f_input_flat = 216'd0;
        threshold_ready = 1'b1;
        observation_valid = 1'b0;
        observation_flat = 3'd0;
        result_ready = 1'b1;
        cycle_count = 0;
        measured_latency = -1;
`ifdef WNS_CLOSURE_ASSERTIONS
        det_capture_valid_d = 1'b0;
        det_round_valid_d = 1'b0;
        det_floor_valid_d = 1'b0;
        det_result_valid_d = 1'b0;
`endif
        requested_steps = MAX_STEPS;
        if ($value$plusargs("STEPS=%d", requested_steps)) begin
            if ((requested_steps < 1) || (requested_steps > MAX_STEPS)) begin
                $display("FAIL: STEPS must be in 1..500");
                $fatal(1);
            end
        end

        $readmemh("vectors/nominal/common/init_state.mem", init_state_mem);
        $readmemh("vectors/nominal/common/init_cov.mem", init_cov_mem);
        $readmemh("vectors/nominal/bkf_l1/f_matrix.mem", f_mem);
        $readmemh("vectors/nominal/bkf_l1/measurement.mem", measurement_mem);
        $readmemh("vectors/nominal/bkf_l1/expected_threshold.mem", threshold_expected_mem);
        $readmemh("vectors/nominal/bkf_l1/branch_observation_bits.mem", observation_expected_mem);
        $readmemh("vectors/nominal/bkf_l1/expected_state.mem", state_expected_mem);
        $readmemh("vectors/nominal/bkf_l1/expected_cov.mem", cov_expected_mem);
        $readmemh("vectors/nominal/bkf_l1/expected_cov_predict.mem", cov_predict_expected_mem);
        $readmemh("vectors/nominal/bkf_l1/expected_reduced_cov.mem", sign_cov_expected_mem);
        $readmemh("vectors/nominal/bkf_l1/expected_gain.mem", gain_expected_mem);
        $readmemh("vectors/nominal/bkf_l1/expected_determinant.mem", determinant_expected_mem);

        if ($test$plusargs("WAVE"))
            rtl_file = $fopen("results/waveform/bkf_smoke.csv", "w");
        else
            rtl_file = $fopen("results/rtl_bkf_l1_outputs.csv", "w");
        if ($test$plusargs("WAVE"))
            mismatch_file = $fopen("results/waveform/bkf_smoke_mismatch.csv", "w");
        else
            mismatch_file = $fopen("results/mismatch_report.csv", "w");
        if ($test$plusargs("WAVE"))
            cycle_file = $fopen("results/waveform/bkf_smoke_cycles.csv", "w");
        else
            cycle_file = $fopen("results/cycle_counts_bkf_l1.csv", "w");
        if ((rtl_file == 0) || (mismatch_file == 0) || (cycle_file == 0)) begin
            $display("FAIL: could not open result files");
            $fatal(1);
        end
        $fdisplay(rtl_file, "step,cycles,threshold_0_int,threshold_1_int,threshold_2_int,observation_0,observation_1,observation_2,state_0_int,state_1_int,state_2_int,cov_00_int,cov_01_int,cov_02_int,cov_10_int,cov_11_int,cov_12_int,cov_20_int,cov_21_int,cov_22_int,overflow,numeric_error,solver_error");
        $fdisplay(mismatch_file, "step,signal,element,expected,actual,cycle");
        $fdisplay(cycle_file, "step,start_cycle,result_cycle,cycles");

        if ($test$plusargs("WAVE")) begin
            $dumpfile("results/waveform/bkf_smoke.vcd");
            $dumpvars(0, tb_bkf_full);
        end

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        if (^state_out_flat === 1'bx || ^cov_out_flat === 1'bx ||
            ^threshold_flat === 1'bx || ^fsm_state === 1'bx) begin
            $display("FAIL: X/Z visible after reset");
            $fatal(1);
        end

        cfg_state_flat = init_state_mem[0];
        cfg_cov_flat = init_cov_mem[0];
        cfg_valid = 1'b1;
        while (!cfg_ready) @(negedge clk);
        @(negedge clk);
        cfg_valid = 1'b0;

        for (step = 0; step < requested_steps; step = step + 1) begin
            while (!model_ready) @(negedge clk);
            f_input_flat = f_mem[step];
            model_valid = 1'b1;
            sample_start_cycle = cycle_count;
            @(negedge clk);
            model_valid = 1'b0;

            while (!threshold_valid) @(negedge clk);
            if (threshold_flat !== threshold_expected_mem[step]) begin
                for (channel = 0; channel < 3; channel = channel + 1) begin
                    if ($signed(threshold_flat[(channel*24) +: 24]) !==
                        $signed(threshold_expected_mem[step][(channel*24) +: 24]))
                        fail_mismatch(step, "threshold", channel,
                            $signed(threshold_expected_mem[step][(channel*24) +: 24]),
                            $signed(threshold_flat[(channel*24) +: 24]));
                end
            end

            generated_observation = 3'd0;
            for (channel = 0; channel < 3; channel = channel + 1) begin
                measurement_element = $signed(measurement_mem[step][(channel*24) +: 24]);
                threshold_element = $signed(threshold_flat[(channel*24) +: 24]);
                generated_observation[channel] = (measurement_element >= threshold_element);
            end
            if (generated_observation !== observation_expected_mem[step])
                fail_mismatch(step, "observation", 0, observation_expected_mem[step], generated_observation);

            // The threshold handshake occurs at the next rising edge. Drive observation only afterward.
            @(negedge clk);
            while (!observation_ready) @(negedge clk);
            observation_flat = generated_observation;
            observation_valid = 1'b1;
            @(negedge clk);
            observation_valid = 1'b0;

            while (!result_valid) @(negedge clk);
            if (measured_latency < 0)
                measured_latency = cycle_count - sample_start_cycle;
            else if ((cycle_count - sample_start_cycle) != measured_latency)
                fail_mismatch(step, "latency", 0, measured_latency,
                              cycle_count - sample_start_cycle);

            if (debug_cov_predict_flat !== cov_predict_expected_mem[step]) begin
                for (matrix_element = 0; matrix_element < 9; matrix_element = matrix_element + 1) begin
                    if ($signed(debug_cov_predict_flat[(matrix_element*24) +: 24]) !==
                        $signed(cov_predict_expected_mem[step][(matrix_element*24) +: 24]))
                        fail_mismatch(step, "cov_predict", matrix_element,
                            $signed(cov_predict_expected_mem[step][(matrix_element*24) +: 24]),
                            $signed(debug_cov_predict_flat[(matrix_element*24) +: 24]));
                end
            end
            if (debug_sign_cov_flat !== sign_cov_expected_mem[step]) begin
                for (matrix_element = 0; matrix_element < 9; matrix_element = matrix_element + 1) begin
                    if ($signed(debug_sign_cov_flat[(matrix_element*24) +: 24]) !==
                        $signed(sign_cov_expected_mem[step][(matrix_element*24) +: 24]))
                        fail_mismatch(step, "sign_cov", matrix_element,
                            $signed(sign_cov_expected_mem[step][(matrix_element*24) +: 24]),
                            $signed(debug_sign_cov_flat[(matrix_element*24) +: 24]));
                end
            end
            if ($signed(debug_determinant) !== $signed(determinant_expected_mem[step]))
                fail_mismatch(step, "determinant", 0, $signed(determinant_expected_mem[step]), $signed(debug_determinant));
            if (debug_gain_flat !== gain_expected_mem[step]) begin
                for (matrix_element = 0; matrix_element < 9; matrix_element = matrix_element + 1) begin
                    if ($signed(debug_gain_flat[(matrix_element*24) +: 24]) !==
                        $signed(gain_expected_mem[step][(matrix_element*24) +: 24]))
                        fail_mismatch(step, "gain", matrix_element,
                            $signed(gain_expected_mem[step][(matrix_element*24) +: 24]),
                            $signed(debug_gain_flat[(matrix_element*24) +: 24]));
                end
            end
            if (state_out_flat !== state_expected_mem[step]) begin
                for (channel = 0; channel < 3; channel = channel + 1) begin
                    if ($signed(state_out_flat[(channel*24) +: 24]) !==
                        $signed(state_expected_mem[step][(channel*24) +: 24]))
                        fail_mismatch(step, "state_post", channel,
                            $signed(state_expected_mem[step][(channel*24) +: 24]),
                            $signed(state_out_flat[(channel*24) +: 24]));
                end
            end
            if (cov_out_flat !== cov_expected_mem[step]) begin
                for (matrix_element = 0; matrix_element < 9; matrix_element = matrix_element + 1) begin
                    if ($signed(cov_out_flat[(matrix_element*24) +: 24]) !==
                        $signed(cov_expected_mem[step][(matrix_element*24) +: 24]))
                        fail_mismatch(step, "cov_post", matrix_element,
                            $signed(cov_expected_mem[step][(matrix_element*24) +: 24]),
                            $signed(cov_out_flat[(matrix_element*24) +: 24]));
                end
            end
            if (overflow_flag || numeric_error || solver_error)
                fail_mismatch(step, "error_flags", 0, 0, {29'd0, overflow_flag, numeric_error, solver_error});

            $fdisplay(rtl_file,
                "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                step, cycle_count-sample_start_cycle,
                $signed(threshold_flat[23:0]), $signed(threshold_flat[47:24]), $signed(threshold_flat[71:48]),
                generated_observation[0] ? 1 : -1,
                generated_observation[1] ? 1 : -1,
                generated_observation[2] ? 1 : -1,
                $signed(state_out_flat[23:0]), $signed(state_out_flat[47:24]), $signed(state_out_flat[71:48]),
                $signed(cov_out_flat[23:0]), $signed(cov_out_flat[47:24]), $signed(cov_out_flat[71:48]),
                $signed(cov_out_flat[95:72]), $signed(cov_out_flat[119:96]), $signed(cov_out_flat[143:120]),
                $signed(cov_out_flat[167:144]), $signed(cov_out_flat[191:168]), $signed(cov_out_flat[215:192]),
                overflow_flag, numeric_error, solver_error);
            $fdisplay(cycle_file, "%0d,%0d,%0d,%0d", step, sample_start_cycle,
                      cycle_count, cycle_count-sample_start_cycle);

            if ($test$plusargs("WAVE") && (step == 4))
                $dumpoff;
            @(negedge clk);
        end

        $fclose(rtl_file);
        $fclose(mismatch_file);
        $fclose(cycle_file);
        if ((accepted_count != requested_steps) || (completion_count != requested_steps)) begin
            $display("FAIL: BKF accepted=%0d completed=%0d expected=%0d",
                     accepted_count, completion_count, requested_steps);
            $fatal(1);
        end
        $display("PASS: %0d/%0d BKF steps matched bit-exactly", requested_steps, requested_steps);
        $finish;
    end

    initial begin
        #(CLK_PERIOD_NS * 800000);
        $display("FAIL: simulation timeout at step %0d state %0d", step, fsm_state);
        $fatal(1);
    end

endmodule

`default_nettype wire
