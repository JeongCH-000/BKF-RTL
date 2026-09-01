`timescale 1ns/1ps
`default_nettype none

module tb_rbkf_full #(
    parameter integer NUM_BRANCHES = 8
);
    localparam integer STEPS = 500;
    localparam integer OBS_WIDTH = 3 * NUM_BRANCHES;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg cfg_valid = 1'b0;
    wire cfg_ready;
    reg [71:0] cfg_state_flat = 72'd0;
    reg [215:0] cfg_cov_flat = 216'd0;
    reg model_valid = 1'b0;
    wire model_ready;
    reg [215:0] f_input_flat = 216'd0;
    wire threshold_valid;
    reg threshold_ready = 1'b1;
    wire [71:0] threshold_flat;
    reg observation_valid = 1'b0;
    wire observation_ready;
    reg [OBS_WIDTH-1:0] branch_observation_bits = {OBS_WIDTH{1'b0}};
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
    wire [71:0] debug_reduced_observation_flat;
    wire [47:0] debug_branch_sum_flat;
    wire [215:0] debug_reduced_cov_flat;
    wire [215:0] debug_gain_flat;
    wire signed [23:0] debug_determinant;

    reg [71:0] init_state [0:0];
    reg [215:0] init_cov [0:0];
    reg [215:0] f_mem [0:STEPS-1];
    reg [71:0] threshold_mem [0:STEPS-1];
    reg [OBS_WIDTH-1:0] bits_mem [0:STEPS-1];
    reg [71:0] reduced_observation_mem [0:STEPS-1];
    reg [215:0] reduced_cov_mem [0:STEPS-1];
    reg [215:0] gain_mem [0:STEPS-1];
    reg [23:0] determinant_mem [0:STEPS-1];
    reg [71:0] state_mem [0:STEPS-1];
    reg [215:0] cov_mem [0:STEPS-1];
    integer step;
    integer cycles;
    integer start_cycle;
    integer requested_steps;
    integer rtl_file;
    integer cycle_file;
    integer accepted_count;
    integer completion_count;
    integer measured_latency;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            accepted_count <= 0;
            completion_count <= 0;
            if (dut.u_engine.pipeline_stage1_valid || dut.u_engine.pipeline_stage2_valid ||
                dut.u_engine.pipeline_stage3_valid || result_valid || done) begin
                $display("FAIL: rBKF pipeline valid/done asserted during reset");
                $fatal(1);
            end
        end else begin
            cycles <= cycles + 1;
            if (model_valid && model_ready) accepted_count <= accepted_count + 1;
            if (result_valid && result_ready) completion_count <= completion_count + 1;
            if ((dut.u_engine.pipeline_stage1_valid && dut.u_engine.pipeline_stage2_valid) ||
                (dut.u_engine.pipeline_stage1_valid && dut.u_engine.pipeline_stage3_valid) ||
                (dut.u_engine.pipeline_stage2_valid && dut.u_engine.pipeline_stage3_valid)) begin
                $display("FAIL: rBKF arithmetic pipeline stages overlap unexpectedly");
                $fatal(1);
            end
            if (dut.u_engine.pipeline_stage1_valid &&
                ((dut.u_engine.u_mul_mac_pipeline.stage1_operation !== dut.u_engine.state) ||
                 (dut.u_engine.u_mul_mac_pipeline.stage1_element_index !== dut.u_engine.element_index) ||
                 (dut.u_engine.u_mul_mac_pipeline.stage1_row_index !== dut.u_engine.row_index) ||
                 (dut.u_engine.u_mul_mac_pipeline.stage1_col_index !== dut.u_engine.col_index) ||
                 (dut.u_engine.u_mul_mac_pipeline.stage1_dot_index !== dut.u_engine.dot_index))) begin
                $display("FAIL: rBKF stage1 metadata is not synchronized");
                $fatal(1);
            end
            if (dut.u_engine.pipeline_stage2_valid &&
                (dut.u_engine.u_mul_mac_pipeline.stage2_operation !== dut.u_engine.state)) begin
                $display("FAIL: rBKF stage2 operation metadata is not synchronized");
                $fatal(1);
            end
            if (dut.u_engine.pipeline_stage3_valid &&
                ((dut.u_engine.pipe_result_operation !== dut.u_engine.state) ||
                 (dut.u_engine.pipe_result_element_index !== dut.u_engine.element_index) ||
                 (dut.u_engine.pipe_result_row_index !== dut.u_engine.row_index) ||
                 (dut.u_engine.pipe_result_col_index !== dut.u_engine.col_index) ||
                 (dut.u_engine.pipe_result_dot_index !== dut.u_engine.dot_index))) begin
                $display("FAIL: rBKF stage3 metadata is not synchronized");
                $fatal(1);
            end
            if (result_valid && ((^state_out_flat === 1'bx) || (^cov_out_flat === 1'bx))) begin
                $display("FAIL: rBKF output contains X/Z while valid");
                $fatal(1);
            end
        end
    end

    rbkf_core #(.NUM_BRANCHES(NUM_BRANCHES)) dut (
        .clk(clk), .rst_n(rst_n), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_state_flat(cfg_state_flat), .cfg_cov_flat(cfg_cov_flat),
        .model_valid(model_valid), .model_ready(model_ready), .f_input_flat(f_input_flat),
        .threshold_valid(threshold_valid), .threshold_ready(threshold_ready),
        .threshold_flat(threshold_flat), .observation_valid(observation_valid),
        .observation_ready(observation_ready), .branch_observation_bits(branch_observation_bits),
        .result_valid(result_valid), .result_ready(result_ready),
        .state_out_flat(state_out_flat), .cov_out_flat(cov_out_flat),
        .busy(busy), .done(done), .overflow_flag(overflow_flag),
        .numeric_error(numeric_error), .solver_error(solver_error), .fsm_state(fsm_state),
        .debug_reduced_observation_flat(debug_reduced_observation_flat),
        .debug_branch_sum_flat(debug_branch_sum_flat),
        .debug_reduced_cov_flat(debug_reduced_cov_flat), .debug_gain_flat(debug_gain_flat),
        .debug_determinant(debug_determinant)
    );

    task fail;
        input [8*32-1:0] signal_name;
        begin
            $display("FAIL: rBKF L=%0d step=%0d signal=%0s state=%0d cycle=%0d",
                     NUM_BRANCHES, step, signal_name, fsm_state, cycles);
            $fatal(1);
        end
    endtask

    initial begin
        cycles = 0;
        measured_latency = -1;
        requested_steps = STEPS;
        if (!$value$plusargs("STEPS=%d", requested_steps)) requested_steps = STEPS;
        $readmemh("vectors/nominal/common/init_state.mem", init_state);
        $readmemh("vectors/nominal/common/init_cov.mem", init_cov);
        if (NUM_BRANCHES == 1) begin
            $readmemh("vectors/nominal/rbkf_l1/f_matrix.mem", f_mem);
            $readmemh("vectors/nominal/rbkf_l1/expected_threshold.mem", threshold_mem);
            $readmemh("vectors/nominal/rbkf_l1/branch_observation_bits.mem", bits_mem);
            $readmemh("vectors/nominal/rbkf_l1/expected_reduced_observation.mem", reduced_observation_mem);
            $readmemh("vectors/nominal/rbkf_l1/expected_reduced_cov.mem", reduced_cov_mem);
            $readmemh("vectors/nominal/rbkf_l1/expected_gain.mem", gain_mem);
            $readmemh("vectors/nominal/rbkf_l1/expected_determinant.mem", determinant_mem);
            $readmemh("vectors/nominal/rbkf_l1/expected_state.mem", state_mem);
            $readmemh("vectors/nominal/rbkf_l1/expected_cov.mem", cov_mem);
        end else begin
            $readmemh("vectors/nominal/rbkf_l8/f_matrix.mem", f_mem);
            $readmemh("vectors/nominal/rbkf_l8/expected_threshold.mem", threshold_mem);
            $readmemh("vectors/nominal/rbkf_l8/branch_observation_bits.mem", bits_mem);
            $readmemh("vectors/nominal/rbkf_l8/expected_reduced_observation.mem", reduced_observation_mem);
            $readmemh("vectors/nominal/rbkf_l8/expected_reduced_cov.mem", reduced_cov_mem);
            $readmemh("vectors/nominal/rbkf_l8/expected_gain.mem", gain_mem);
            $readmemh("vectors/nominal/rbkf_l8/expected_determinant.mem", determinant_mem);
            $readmemh("vectors/nominal/rbkf_l8/expected_state.mem", state_mem);
            $readmemh("vectors/nominal/rbkf_l8/expected_cov.mem", cov_mem);
        end
        if ($test$plusargs("WAVE")) begin
            $dumpfile("results/waveform/rbkf_smoke.vcd");
            $dumpvars(0, tb_rbkf_full);
        end
        if ($test$plusargs("WAVE")) begin
            rtl_file = $fopen("results/waveform/rbkf_smoke.csv", "w");
            cycle_file = $fopen("results/waveform/rbkf_smoke_cycles.csv", "w");
        end else if (NUM_BRANCHES == 1) begin
            rtl_file = $fopen("results/rtl_rbkf_l1_outputs.csv", "w");
            cycle_file = $fopen("results/cycle_counts_rbkf_l1.csv", "w");
        end else begin
            rtl_file = $fopen("results/rtl_rbkf_l8_outputs.csv", "w");
            cycle_file = $fopen("results/cycle_counts_rbkf_l8.csv", "w");
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
            while (!model_ready) @(negedge clk);
            f_input_flat = f_mem[step];
            model_valid = 1'b1;
            start_cycle = cycles;
            @(negedge clk);
            model_valid = 1'b0;
            while (!threshold_valid) @(negedge clk);
            if (threshold_flat !== threshold_mem[step]) fail("threshold");
            @(negedge clk);
            while (!observation_ready) @(negedge clk);
            branch_observation_bits = bits_mem[step];
            observation_valid = 1'b1;
            @(negedge clk);
            observation_valid = 1'b0;
            while (!result_valid) @(negedge clk);
            if (measured_latency < 0)
                measured_latency = cycles - start_cycle;
            else if ((cycles - start_cycle) != measured_latency)
                fail("latency_variation");
            if (debug_reduced_observation_flat !== reduced_observation_mem[step]) fail("reduced_observation");
            if (debug_reduced_cov_flat !== reduced_cov_mem[step]) fail("reduced_covariance");
            if (debug_gain_flat !== gain_mem[step]) fail("gain");
            if ($signed(debug_determinant) !== $signed(determinant_mem[step])) fail("determinant");
            if (state_out_flat !== state_mem[step]) fail("state");
            if (cov_out_flat !== cov_mem[step]) fail("covariance");
            if (overflow_flag || numeric_error || solver_error) fail("error_flags");
            $fdisplay(cycle_file, "%0d,%0d,%0d,%0d", step, start_cycle,
                      cycles, cycles-start_cycle);
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
            $display("FAIL: rBKF L=%0d accepted=%0d completed=%0d expected=%0d",
                     NUM_BRANCHES, accepted_count, completion_count, requested_steps);
            $fatal(1);
        end
        $display("PASS: %0d/%0d rBKF L=%0d steps matched bit-exactly", requested_steps, requested_steps, NUM_BRANCHES);
        $finish;
    end

    initial begin
        #10000000;
        $display("FAIL: rBKF timeout L=%0d step=%0d state=%0d", NUM_BRANCHES, step, fsm_state);
        $fatal(1);
    end
endmodule

`default_nettype wire
