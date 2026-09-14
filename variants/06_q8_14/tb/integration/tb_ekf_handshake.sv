`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

module tb_ekf_handshake;
    `include "tb/unit/fx_format_tb.vh"
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg cfg_valid = 1'b0;
    wire cfg_ready;
    reg [3*W-1:0] cfg_state_flat = {3*W{1'b0}};
    reg [9*W-1:0] cfg_cov_flat = {9*W{1'b0}};
    reg input_valid = 1'b0;
    wire input_ready;
    reg [9*W-1:0] f_input_flat = {9*W{1'b0}};
    reg [3*W-1:0] measurement_flat = {3*W{1'b0}};
    wire result_valid;
    reg result_ready = 1'b0;
    wire [3*W-1:0] state_out_flat;
    wire [9*W-1:0] cov_out_flat;
    wire busy;
    wire done;
    wire overflow_flag;
    wire numeric_error;
    wire solver_error;
    wire [5:0] fsm_state;
    reg [3*W-1:0] init_state [0:0];
    reg [9*W-1:0] init_cov [0:0];
    reg [9*W-1:0] f_mem [0:499];
    reg [3*W-1:0] measurement_mem [0:499];
    reg [3*W-1:0] state_mem [0:499];
    reg [9*W-1:0] cov_mem [0:499];
    reg [3*W-1:0] held_state;
    reg [9*W-1:0] held_cov;
    integer index;

    always #5 clk = ~clk;

    ekf_core dut (
        .clk(clk), .rst_n(rst_n), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_state_flat(cfg_state_flat), .cfg_cov_flat(cfg_cov_flat),
        .input_valid(input_valid), .input_ready(input_ready),
        .f_input_flat(f_input_flat), .measurement_flat(measurement_flat),
        .result_valid(result_valid), .result_ready(result_ready),
        .state_out_flat(state_out_flat), .cov_out_flat(cov_out_flat),
        .busy(busy), .done(done), .overflow_flag(overflow_flag),
        .numeric_error(numeric_error), .solver_error(solver_error), .fsm_state(fsm_state)
    );

    initial begin
        $readmemh("vectors/nominal/common/init_state.mem", init_state);
        $readmemh("vectors/nominal/common/init_cov.mem", init_cov);
        $readmemh("vectors/nominal/ekf/f_matrix.mem", f_mem);
        $readmemh("vectors/nominal/ekf/measurement.mem", measurement_mem);
        $readmemh("vectors/nominal/ekf/expected_state.mem", state_mem);
        $readmemh("vectors/nominal/ekf/expected_cov.mem", cov_mem);
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        cfg_state_flat = init_state[0];
        cfg_cov_flat = init_cov[0];
        cfg_valid = 1'b1;
        @(negedge clk);
        cfg_valid = 1'b0;
        #1;
        for (index = 0; index < 3; index = index + 1) begin
            if (!input_ready || busy) $fatal(1, "FAIL: EKF input ready while producer late");
            @(negedge clk);
        end
        f_input_flat = f_mem[0];
        measurement_flat = measurement_mem[0];
        input_valid = 1'b1;
        @(negedge clk);
        input_valid = 1'b0;
        while (!result_valid) @(negedge clk);
        held_state = state_out_flat;
        held_cov = cov_out_flat;
        if (held_state !== state_mem[0] || held_cov !== cov_mem[0])
            $fatal(1, "FAIL: EKF result mismatch before backpressure");
        for (index = 0; index < 3; index = index + 1) begin
            @(negedge clk);
            if (!result_valid || state_out_flat !== held_state || cov_out_flat !== held_cov || !busy)
                $fatal(1, "FAIL: EKF result changed under backpressure");
        end
        result_ready = 1'b1;
        @(negedge clk);
        result_ready = 1'b0;
        #1;
        if (!input_ready || busy)
            $fatal(1, "FAIL: EKF did not return cleanly to idle");
        $display("PASS: EKF input delay and result backpressure");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL: EKF handshake timeout state=%0d", fsm_state);
    end
endmodule

`default_nettype wire
