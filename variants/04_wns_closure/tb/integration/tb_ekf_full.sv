`timescale 1ns/1ps
`default_nettype none

module tb_ekf_full;
    localparam integer STEPS = 500;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg cfg_valid = 1'b0;
    wire cfg_ready;
    reg [71:0] cfg_state_flat = 72'd0;
    reg [215:0] cfg_cov_flat = 216'd0;
    reg input_valid = 1'b0;
    wire input_ready;
    reg [215:0] f_input_flat = 216'd0;
    reg [71:0] measurement_flat = 72'd0;
    wire result_valid;
    reg result_ready = 1'b1;
    wire [71:0] state_out_flat;
    wire [215:0] cov_out_flat;
    wire busy;
    wire done;
    wire overflow_flag;
    wire numeric_error;
    wire solver_error;
    wire [5:0] fsm_state;
    wire [215:0] debug_cov_predict_flat;
    wire [215:0] debug_innovation_cov_flat;
    wire [215:0] debug_gain_flat;
    wire [71:0] debug_innovation_flat;
    wire signed [23:0] debug_determinant;

    reg [71:0] init_state [0:0];
    reg [215:0] init_cov [0:0];
    reg [215:0] f_mem [0:STEPS-1];
    reg [71:0] measurement_mem [0:STEPS-1];
    reg [215:0] cov_inner_mem [0:STEPS-1];
    reg [215:0] cov_predict_mem [0:STEPS-1];
    reg [215:0] innovation_cov_mem [0:STEPS-1];
    reg [215:0] gain_mem [0:STEPS-1];
    reg [23:0] determinant_mem [0:STEPS-1];
    reg [71:0] state_mem [0:STEPS-1];
    reg [215:0] cov_mem [0:STEPS-1];
    integer step;
    integer requested_steps;
    integer rtl_file;
    integer cycle_file;
    integer cycle_count;
    integer start_cycle;
    integer accepted_count;
    integer completion_count;
    integer measured_latency;
    integer matrix_check_index;

`ifdef WNS_CLOSURE_ASSERTIONS
    reg det_capture_valid_d = 1'b0;
    reg det_round_valid_d = 1'b0;
    reg det_floor_valid_d = 1'b0;
    reg det_result_valid_d = 1'b0;

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

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            accepted_count <= 0;
            completion_count <= 0;
            if (dut.u_engine.pipeline_stage1_valid || dut.u_engine.pipeline_stage2_valid ||
                dut.u_engine.pipeline_stage3_valid || result_valid || done) begin
                $display("FAIL: EKF pipeline valid/done asserted during reset");
                $fatal(1);
            end
`ifdef WNS_CLOSURE_ASSERTIONS
            det_capture_valid_d <= 1'b0;
            det_round_valid_d <= 1'b0;
            det_floor_valid_d <= 1'b0;
            det_result_valid_d <= 1'b0;
            if (dut.u_engine.cov_predict_mac_valid || dut.u_engine.add_q_operand_valid ||
                dut.u_engine.cov_sym_operand_valid || dut.u_engine.measurement_operand_valid ||
                dut.u_engine.measurement_sym_operand_valid || dut.u_engine.sign_sym_operand_valid ||
                dut.u_engine.self_reduce_operand_valid || dut.u_engine.ekf_sign_copy_valid ||
                dut.u_engine.post_sym_operand_valid || dut.u_engine.branch_reduction_valid ||
                dut.u_engine.det_capture_stage_valid || dut.u_engine.det_round_stage_valid ||
                dut.u_engine.det_floor_stage_valid || dut.u_engine.det_finalize_valid) begin
                $display("FAIL: EKF WNS-closure valid asserted during reset");
                $fatal(1);
            end
`endif
        end else begin
            cycle_count <= cycle_count + 1;
            if (input_valid && input_ready) accepted_count <= accepted_count + 1;
            if (result_valid && result_ready) completion_count <= completion_count + 1;
            if ((dut.u_engine.pipeline_stage1_valid && dut.u_engine.pipeline_stage2_valid) ||
                (dut.u_engine.pipeline_stage1_valid && dut.u_engine.pipeline_stage3_valid) ||
                (dut.u_engine.pipeline_stage2_valid && dut.u_engine.pipeline_stage3_valid)) begin
                $display("FAIL: EKF arithmetic pipeline stages overlap unexpectedly");
                $fatal(1);
            end
            if (dut.u_engine.pipeline_stage1_valid &&
                ((dut.u_engine.u_mul_mac_pipeline.stage1_operation !== dut.u_engine.state) ||
                 (dut.u_engine.u_mul_mac_pipeline.stage1_element_index !== dut.u_engine.element_index) ||
                 (dut.u_engine.u_mul_mac_pipeline.stage1_row_index !== dut.u_engine.row_index) ||
                 (dut.u_engine.u_mul_mac_pipeline.stage1_col_index !== dut.u_engine.col_index) ||
                 (dut.u_engine.u_mul_mac_pipeline.stage1_dot_index !== dut.u_engine.dot_index))) begin
                $display("FAIL: EKF stage1 metadata is not synchronized");
                $fatal(1);
            end
            if (dut.u_engine.pipeline_stage2_valid &&
                (dut.u_engine.u_mul_mac_pipeline.stage2_operation !== dut.u_engine.state)) begin
                $display("FAIL: EKF stage2 operation metadata is not synchronized");
                $fatal(1);
            end
            if (dut.u_engine.pipeline_stage3_valid &&
                ((dut.u_engine.pipe_result_operation !== dut.u_engine.state) ||
                 (dut.u_engine.pipe_result_element_index !== dut.u_engine.element_index) ||
                 (dut.u_engine.pipe_result_row_index !== dut.u_engine.row_index) ||
                 (dut.u_engine.pipe_result_col_index !== dut.u_engine.col_index) ||
                 (dut.u_engine.pipe_result_dot_index !== dut.u_engine.dot_index))) begin
                $display("FAIL: EKF stage3 metadata is not synchronized");
                $fatal(1);
            end
            if (result_valid && ((^state_out_flat === 1'bx) || (^cov_out_flat === 1'bx))) begin
                $display("FAIL: EKF output contains X/Z while valid");
                $fatal(1);
            end
`ifdef WNS_CLOSURE_ASSERTIONS
            if ((^{dut.u_engine.cov_predict_mac_valid, dut.u_engine.add_q_operand_valid,
                   dut.u_engine.cov_sym_operand_valid, dut.u_engine.measurement_operand_valid,
                   dut.u_engine.measurement_sym_operand_valid, dut.u_engine.sign_sym_operand_valid,
                   dut.u_engine.self_reduce_operand_valid, dut.u_engine.ekf_sign_copy_valid,
                   dut.u_engine.post_sym_operand_valid} === 1'bx) ||
                !valid_zero_or_onehot9({dut.u_engine.cov_predict_mac_valid, dut.u_engine.add_q_operand_valid,
                           dut.u_engine.cov_sym_operand_valid, dut.u_engine.measurement_operand_valid,
                           dut.u_engine.measurement_sym_operand_valid, dut.u_engine.sign_sym_operand_valid,
                           dut.u_engine.self_reduce_operand_valid, dut.u_engine.ekf_sign_copy_valid,
                           dut.u_engine.post_sym_operand_valid})) begin
                $display("FAIL: EKF local writeback valids overlap or contain X/Z values=%b",
                    {dut.u_engine.cov_predict_mac_valid, dut.u_engine.add_q_operand_valid,
                     dut.u_engine.cov_sym_operand_valid, dut.u_engine.measurement_operand_valid,
                     dut.u_engine.measurement_sym_operand_valid, dut.u_engine.sign_sym_operand_valid,
                     dut.u_engine.self_reduce_operand_valid, dut.u_engine.ekf_sign_copy_valid,
                     dut.u_engine.post_sym_operand_valid});
                $fatal(1);
            end
            if (dut.u_engine.cov_predict_mac_valid &&
                ((dut.u_engine.state !== dut.u_engine.ST_COV_OUTER_COMMIT) ||
                 !valid_onehot9(dut.u_engine.cov_predict_mac_write_mask_reg) ||
                 (dut.u_engine.cov_predict_mac_write_mask_reg[
                    (dut.u_engine.cov_predict_mac_row_reg*3)+dut.u_engine.cov_predict_mac_col_reg] !== 1'b1) ||
                 (dut.u_engine.cov_predict_mac_last_reg !==
                    ((dut.u_engine.cov_predict_mac_row_reg == 2'd2) &&
                     (dut.u_engine.cov_predict_mac_col_reg == 2'd2))))) begin
                $display("FAIL: EKF cov_predict writeback data/metadata mismatch");
                $fatal(1);
            end
            if (dut.u_engine.add_q_operand_valid &&
                ((dut.u_engine.state !== dut.u_engine.ST_ADD_Q_COMMIT) ||
                 !valid_onehot9(dut.u_engine.add_q_write_mask_reg) ||
                 (dut.u_engine.add_q_last_reg !== dut.u_engine.add_q_write_mask_reg[8]))) begin
                $display("FAIL: EKF add-Q writeback data/metadata mismatch");
                $fatal(1);
            end
            if (dut.u_engine.cov_sym_operand_valid &&
                ((dut.u_engine.state !== dut.u_engine.ST_SYM_SIG_COMMIT) ||
                 !valid_symmetric_mask(dut.u_engine.cov_sym_write_mask_reg) ||
                 (dut.u_engine.cov_sym_last_reg !==
                    (dut.u_engine.cov_sym_write_mask_reg == 9'b010100000)))) begin
                $display("FAIL: EKF covariance symmetry data/metadata mismatch");
                $fatal(1);
            end
            if (dut.u_engine.measurement_operand_valid &&
                ((dut.u_engine.state !== dut.u_engine.ST_P_BUILD_COMMIT) ||
                 !valid_onehot9(dut.u_engine.measurement_write_mask_reg) ||
                 (dut.u_engine.measurement_last_reg !== dut.u_engine.measurement_write_mask_reg[8]))) begin
                $display("FAIL: EKF measurement writeback data/metadata mismatch");
                $fatal(1);
            end
            if (dut.u_engine.measurement_sym_operand_valid &&
                ((dut.u_engine.state !== dut.u_engine.ST_P_SYM_COMMIT) ||
                 !valid_symmetric_mask(dut.u_engine.measurement_sym_write_mask_reg) ||
                 (dut.u_engine.measurement_sym_last_reg !==
                    (dut.u_engine.measurement_sym_write_mask_reg == 9'b010100000)))) begin
                $display("FAIL: EKF measurement symmetry data/metadata mismatch");
                $fatal(1);
            end
            if (dut.u_engine.sign_sym_operand_valid &&
                ((dut.u_engine.state !== dut.u_engine.ST_S_SYM_COMMIT) ||
                 !valid_symmetric_mask(dut.u_engine.sign_sym_write_mask_reg) ||
                 (dut.u_engine.sign_sym_last_reg !==
                    (dut.u_engine.sign_sym_write_mask_reg == 9'b010100000)))) begin
                $display("FAIL: EKF sign symmetry data/metadata mismatch");
                $fatal(1);
            end
            if (dut.u_engine.self_reduce_operand_valid &&
                ((dut.u_engine.state !== dut.u_engine.ST_SELF_REDUCE_COMMIT) ||
                 !valid_onehot9(dut.u_engine.self_reduce_write_mask_reg) ||
                 (|(dut.u_engine.self_reduce_write_mask_reg & 9'b011101110)) ||
                 (dut.u_engine.self_reduce_last_reg !== dut.u_engine.self_reduce_write_mask_reg[8]))) begin
                $display("FAIL: EKF self-reduction data/metadata mismatch");
                $fatal(1);
            end
            if (dut.u_engine.ekf_sign_copy_valid &&
                ((dut.u_engine.state !== dut.u_engine.ST_EKF_S_COPY_COMMIT) ||
                 !valid_onehot9(dut.u_engine.ekf_sign_copy_write_mask_reg) ||
                 (dut.u_engine.ekf_sign_copy_last_reg !== dut.u_engine.ekf_sign_copy_write_mask_reg[8]))) begin
                $display("FAIL: EKF sign-copy data/metadata mismatch");
                $fatal(1);
            end
            if (dut.u_engine.post_sym_operand_valid &&
                ((dut.u_engine.state !== dut.u_engine.ST_POST_SYM_COMMIT) ||
                 !valid_symmetric_mask(dut.u_engine.post_sym_write_mask_reg) ||
                 (dut.u_engine.post_sym_last_reg !==
                    (dut.u_engine.post_sym_write_mask_reg == 9'b010100000)))) begin
                $display("FAIL: EKF posterior symmetry data/metadata mismatch");
                $fatal(1);
            end
            if ((^{dut.u_engine.det_capture_stage_valid, dut.u_engine.det_round_stage_valid,
                   dut.u_engine.det_floor_stage_valid, dut.u_engine.det_finalize_valid} === 1'bx) ||
                !valid_zero_or_onehot4({dut.u_engine.det_capture_stage_valid, dut.u_engine.det_round_stage_valid,
                           dut.u_engine.det_floor_stage_valid, dut.u_engine.det_finalize_valid}) ||
                ((dut.u_engine.det_capture_stage_valid || dut.u_engine.det_round_stage_valid ||
                  dut.u_engine.det_floor_stage_valid || dut.u_engine.det_finalize_valid) &&
                 (dut.u_engine.state !== dut.u_engine.ST_DET_WAIT))) begin
                $display("FAIL: EKF determinant stage valid/state mismatch");
                $fatal(1);
            end
            if ((dut.u_engine.det_round_stage_valid && !det_round_valid_d && !det_capture_valid_d) ||
                (dut.u_engine.det_floor_stage_valid && !det_floor_valid_d && !det_round_valid_d) ||
                (dut.u_engine.det_finalize_valid && !det_result_valid_d && !det_floor_valid_d)) begin
                $display("FAIL: EKF determinant valid did not advance with its data");
                $fatal(1);
            end
            if (dut.u_engine.branch_reduction_valid) begin
                $display("FAIL: EKF unexpectedly asserted branch_reduction_valid");
                $fatal(1);
            end
            det_capture_valid_d <= dut.u_engine.det_capture_stage_valid;
            det_round_valid_d <= dut.u_engine.det_round_stage_valid;
            det_floor_valid_d <= dut.u_engine.det_floor_stage_valid;
            det_result_valid_d <= dut.u_engine.det_finalize_valid;
`endif
        end
    end

    ekf_core dut (
        .clk(clk), .rst_n(rst_n), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_state_flat(cfg_state_flat), .cfg_cov_flat(cfg_cov_flat),
        .input_valid(input_valid), .input_ready(input_ready),
        .f_input_flat(f_input_flat), .measurement_flat(measurement_flat),
        .result_valid(result_valid), .result_ready(result_ready),
        .state_out_flat(state_out_flat), .cov_out_flat(cov_out_flat),
        .busy(busy), .done(done), .overflow_flag(overflow_flag),
        .numeric_error(numeric_error), .solver_error(solver_error), .fsm_state(fsm_state),
        .debug_cov_predict_flat(debug_cov_predict_flat),
        .debug_innovation_cov_flat(debug_innovation_cov_flat),
        .debug_gain_flat(debug_gain_flat), .debug_innovation_flat(debug_innovation_flat),
        .debug_determinant(debug_determinant)
    );

    task fail;
        input [8*32-1:0] signal_name;
        begin
            $display("FAIL: EKF step=%0d signal=%0s state=%0d", step, signal_name, fsm_state);
            $fatal(1);
        end
    endtask

    initial begin
        requested_steps = STEPS;
        measured_latency = -1;
        if (!$value$plusargs("STEPS=%d", requested_steps)) requested_steps = STEPS;
        $readmemh("vectors/nominal/common/init_state.mem", init_state);
        $readmemh("vectors/nominal/common/init_cov.mem", init_cov);
        $readmemh("vectors/nominal/ekf/f_matrix.mem", f_mem);
        $readmemh("vectors/nominal/ekf/measurement.mem", measurement_mem);
        $readmemh("vectors/nominal/ekf/expected_cov_inner.mem", cov_inner_mem);
        $readmemh("vectors/nominal/ekf/expected_cov_predict.mem", cov_predict_mem);
        $readmemh("vectors/nominal/ekf/expected_innovation_cov.mem", innovation_cov_mem);
        $readmemh("vectors/nominal/ekf/expected_gain.mem", gain_mem);
        $readmemh("vectors/nominal/ekf/expected_determinant.mem", determinant_mem);
        $readmemh("vectors/nominal/ekf/expected_state.mem", state_mem);
        $readmemh("vectors/nominal/ekf/expected_cov.mem", cov_mem);
        if ($test$plusargs("WAVE")) begin
            $dumpfile("results/waveform/ekf_smoke.vcd");
            $dumpvars(0, tb_ekf_full);
        end
        if ($test$plusargs("WAVE")) begin
            rtl_file = $fopen("results/waveform/ekf_smoke.csv", "w");
            cycle_file = $fopen("results/waveform/ekf_smoke_cycles.csv", "w");
        end else begin
            rtl_file = $fopen("results/rtl_ekf_outputs.csv", "w");
            cycle_file = $fopen("results/cycle_counts_ekf.csv", "w");
        end
        if (rtl_file == 0) fail("open_output");
        if (cycle_file == 0) fail("open_cycles");
        $fdisplay(rtl_file, "step,state_0_int,state_1_int,state_2_int,cov_00_int,cov_01_int,cov_02_int,cov_10_int,cov_11_int,cov_12_int,cov_20_int,cov_21_int,cov_22_int");
        $fdisplay(cycle_file, "step,start_cycle,result_cycle,cycles");
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        cfg_state_flat = init_state[0];
        cfg_cov_flat = init_cov[0];
        cfg_valid = 1'b1;
        @(negedge clk);
        cfg_valid = 1'b0;
        for (step = 0; step < requested_steps; step = step + 1) begin
            while (!input_ready) @(negedge clk);
            f_input_flat = f_mem[step];
            measurement_flat = measurement_mem[step];
            input_valid = 1'b1;
            start_cycle = cycle_count;
            @(negedge clk);
            input_valid = 1'b0;
            for (matrix_check_index = 0; matrix_check_index < 9;
                 matrix_check_index = matrix_check_index + 1) begin
                if ($signed(dut.u_engine.f_matrix[matrix_check_index]) !==
                    $signed(f_mem[step][(matrix_check_index*24) +: 24]))
                    fail("f_matrix_capture");
            end
            while (!result_valid) @(negedge clk);
            if (measured_latency < 0)
                measured_latency = cycle_count - start_cycle;
            else if ((cycle_count - start_cycle) != measured_latency)
                fail("latency_variation");
            for (matrix_check_index = 0; matrix_check_index < 9;
                 matrix_check_index = matrix_check_index + 1) begin
                if ($signed(dut.u_engine.matrix_temp[matrix_check_index]) !==
                    $signed(cov_inner_mem[step][(matrix_check_index*24) +: 24]))
                    fail("covariance_inner");
            end
            if (debug_cov_predict_flat !== cov_predict_mem[step]) fail("cov_predict");
            if (debug_innovation_cov_flat !== innovation_cov_mem[step]) fail("innovation_covariance");
            if (debug_gain_flat !== gain_mem[step]) fail("gain");
            if ($signed(debug_determinant) !== $signed(determinant_mem[step])) fail("determinant");
            if (state_out_flat !== state_mem[step]) fail("state");
            if (cov_out_flat !== cov_mem[step]) fail("covariance");
            if (overflow_flag || numeric_error || solver_error) fail("error_flags");
            $fdisplay(cycle_file, "%0d,%0d,%0d,%0d", step, start_cycle,
                      cycle_count, cycle_count-start_cycle);
            $fdisplay(rtl_file, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                step, $signed(state_out_flat[23:0]), $signed(state_out_flat[47:24]),
                $signed(state_out_flat[71:48]), $signed(cov_out_flat[23:0]),
                $signed(cov_out_flat[47:24]), $signed(cov_out_flat[71:48]),
                $signed(cov_out_flat[95:72]), $signed(cov_out_flat[119:96]),
                $signed(cov_out_flat[143:120]), $signed(cov_out_flat[167:144]),
                $signed(cov_out_flat[191:168]), $signed(cov_out_flat[215:192]));
            if ($test$plusargs("WAVE") && (step == 4)) $dumpoff;
            @(negedge clk);
        end
        $fclose(rtl_file);
        $fclose(cycle_file);
        if ((accepted_count != requested_steps) || (completion_count != requested_steps)) begin
            $display("FAIL: EKF accepted=%0d completed=%0d expected=%0d",
                     accepted_count, completion_count, requested_steps);
            $fatal(1);
        end
        $display("PASS: %0d/%0d EKF steps matched bit-exactly", requested_steps, requested_steps);
        $finish;
    end

    initial begin
        #10000000;
        $display("FAIL: EKF timeout step=%0d state=%0d", step, fsm_state);
        $fatal(1);
    end
endmodule

`default_nettype wire
