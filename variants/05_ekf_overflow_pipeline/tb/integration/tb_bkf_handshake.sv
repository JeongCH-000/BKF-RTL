`timescale 1ns/1ps
`default_nettype none

module tb_bkf_handshake;
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
    reg threshold_ready = 1'b0;
    wire [71:0] threshold_flat;
    reg observation_valid = 1'b0;
    wire observation_ready;
    reg [2:0] observation_flat = 3'd0;
    wire result_valid;
    reg result_ready = 1'b0;
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

    reg [71:0] init_state [0:0];
    reg [215:0] init_cov [0:0];
    reg [215:0] f_vector [0:499];
    reg [71:0] expected_threshold [0:499];
    reg [2:0] expected_observation [0:499];
    reg [71:0] expected_state [0:499];
    reg [215:0] expected_cov [0:499];
    reg [71:0] held_threshold;
    reg [71:0] held_state;
    reg [215:0] held_cov;
    integer hold_cycle;

    always #5 clk = ~clk;

    bkf_core dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_state_flat(cfg_state_flat), .cfg_cov_flat(cfg_cov_flat),
        .model_valid(model_valid), .model_ready(model_ready), .f_input_flat(f_input_flat),
        .threshold_valid(threshold_valid), .threshold_ready(threshold_ready), .threshold_flat(threshold_flat),
        .observation_valid(observation_valid), .observation_ready(observation_ready), .observation_flat(observation_flat),
        .measurement_flat(72'd0),
        .result_valid(result_valid), .result_ready(result_ready),
        .state_out_flat(state_out_flat), .cov_out_flat(cov_out_flat),
        .busy(busy), .done(done), .overflow_flag(overflow_flag),
        .numeric_error(numeric_error), .solver_error(solver_error), .fsm_state(fsm_state),
        .debug_cov_predict_flat(debug_cov_predict_flat), .debug_sign_cov_flat(debug_sign_cov_flat),
        .debug_gain_flat(debug_gain_flat), .debug_determinant(debug_determinant)
    );

    initial begin
        $readmemh("vectors/nominal/common/init_state.mem", init_state, 0, 0);
        $readmemh("vectors/nominal/common/init_cov.mem", init_cov, 0, 0);
        $readmemh("vectors/nominal/bkf_l1/f_matrix.mem", f_vector);
        $readmemh("vectors/nominal/bkf_l1/expected_threshold.mem", expected_threshold);
        $readmemh("vectors/nominal/bkf_l1/branch_observation_bits.mem", expected_observation);
        $readmemh("vectors/nominal/bkf_l1/expected_state.mem", expected_state);
        $readmemh("vectors/nominal/bkf_l1/expected_cov.mem", expected_cov);

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        if (!cfg_ready || busy || result_valid || threshold_valid || observation_ready) begin
            $display("FAIL: reset handshake state");
            $fatal(1);
        end
        if (^state_out_flat === 1'bx || ^cov_out_flat === 1'bx || ^fsm_state === 1'bx) begin
            $display("FAIL: X/Z after reset");
            $fatal(1);
        end

        cfg_state_flat = init_state[0];
        cfg_cov_flat = init_cov[0];
        cfg_valid = 1'b1;
        @(negedge clk);
        cfg_valid = 1'b0;
        #1;
        if (!model_ready) begin
            $display("FAIL: model_ready did not assert after configuration");
            $fatal(1);
        end

        f_input_flat = f_vector[0];
        model_valid = 1'b1;
        @(negedge clk);
        model_valid = 1'b0;
        if (!busy) begin
            $display("FAIL: busy did not assert");
            $fatal(1);
        end

        while (!threshold_valid) @(negedge clk);
        held_threshold = threshold_flat;
        if (held_threshold !== expected_threshold[0]) begin
            $display("FAIL: threshold value before stall");
            $fatal(1);
        end
        for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
            @(negedge clk);
            if (!threshold_valid || threshold_flat !== held_threshold || observation_ready) begin
                $display("FAIL: threshold valid/payload was not held during backpressure");
                $fatal(1);
            end
        end

        // Complete the threshold handshake, then deliberately delay the producer.
        threshold_ready = 1'b1;
        @(negedge clk);
        threshold_ready = 1'b0;
        for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
            if (!observation_ready || result_valid) begin
                $display("FAIL: observation_ready was not held while producer was late");
                $fatal(1);
            end
            @(negedge clk);
        end
        observation_flat = expected_observation[0];
        observation_valid = 1'b1;
        @(negedge clk);
        observation_valid = 1'b0;

        while (!result_valid) @(negedge clk);
        held_state = state_out_flat;
        held_cov = cov_out_flat;
        if (held_state !== expected_state[0] || held_cov !== expected_cov[0]) begin
            $display("FAIL: result before stall differs from expected");
            $fatal(1);
        end
        for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
            @(negedge clk);
            if (!result_valid || state_out_flat !== held_state || cov_out_flat !== held_cov || !busy) begin
                $display("FAIL: result valid/payload was not held during backpressure");
                $fatal(1);
            end
        end
        if (overflow_flag || numeric_error || solver_error) begin
            $display("FAIL: unexpected error flag");
            $fatal(1);
        end

        result_ready = 1'b1;
        @(negedge clk);
        result_ready = 1'b0;
        #1;
        if (!model_ready || busy || result_valid) begin
            $display("FAIL: core did not return to IDLE after result handshake");
            $fatal(1);
        end

        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        if (^state_out_flat === 1'bx || ^cov_out_flat === 1'bx || state_out_flat !== 0 || cov_out_flat !== 0) begin
            $display("FAIL: reset did not clear visible state");
            $fatal(1);
        end
        $display("PASS: reset and ready/valid backpressure behavior");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: handshake test timeout state=%0d", fsm_state);
        $fatal(1);
    end
endmodule

`default_nettype wire
