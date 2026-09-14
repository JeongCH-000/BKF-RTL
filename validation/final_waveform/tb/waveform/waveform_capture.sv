`timescale 1ns/1ps
`default_nettype none

// Simulation-only observer. Never drives or forces the DUT/testbench.
// WV_TB and WV_CORE select the unchanged integration testbench hierarchy.
module waveform_capture #(
    parameter integer NUM_BRANCHES = 1
);
    wire clk = `WV_TB.clk;
    wire rst_n = `WV_TB.rst_n;
    wire cfg_valid = `WV_CORE.cfg_valid;
    wire cfg_ready = `WV_CORE.cfg_ready;
    wire [71:0] cfg_state_flat = `WV_CORE.cfg_state_flat;
    wire [215:0] cfg_cov_flat = `WV_CORE.cfg_cov_flat;
    wire input_valid = `WV_CORE.model_valid;
    wire input_ready = `WV_CORE.model_ready;
    wire [215:0] f_input_flat = `WV_CORE.f_input_flat;
    wire [71:0] measurement_flat = `WV_CORE.measurement_flat;
    wire threshold_valid = `WV_CORE.threshold_valid;
    wire threshold_ready = `WV_CORE.threshold_ready;
    wire [71:0] threshold_flat = `WV_CORE.threshold_flat;
    wire observation_valid = `WV_CORE.observation_valid;
    wire observation_ready = `WV_CORE.observation_ready;
    wire [(3*NUM_BRANCHES)-1:0] branch_observation_bits = `WV_CORE.observation_flat;
    wire result_valid = `WV_CORE.result_valid;
    wire result_ready = `WV_CORE.result_ready;
    wire [71:0] state_out_flat = `WV_CORE.state_out_flat;
    wire [215:0] cov_out_flat = `WV_CORE.cov_out_flat;
    wire busy = `WV_CORE.busy;
    wire done = `WV_CORE.done;
    wire overflow_flag = `WV_CORE.overflow_flag;
    wire numeric_error = `WV_CORE.numeric_error;
    wire solver_error = `WV_CORE.solver_error;
    wire [5:0] fsm_state = `WV_CORE.fsm_state;
    wire signed [23:0] state_x = $signed(state_out_flat[23:0]);
    wire signed [23:0] state_y = $signed(state_out_flat[47:24]);
    wire signed [23:0] state_z = $signed(state_out_flat[71:48]);
    wire signed [23:0] cov_00 = $signed(cov_out_flat[23:0]);
    wire signed [23:0] cov_11 = $signed(cov_out_flat[119:96]);
    wire signed [23:0] cov_22 = $signed(cov_out_flat[215:192]);

    // Read-only array aliases: recursive Icarus dumps omit unpacked memories.
    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : vector_element
            wire signed [23:0] state_post = `WV_CORE.state_post[i];
            wire signed [23:0] state_predict = `WV_CORE.state_predict[i];
            wire signed [23:0] measurement_hold = `WV_CORE.measurement_hold[i];
            wire signed [23:0] observation_q = `WV_CORE.observation_q[i];
            wire signed [23:0] state_correction = `WV_CORE.state_correction[i];
            wire signed [15:0] branch_sum = `WV_CORE.branch_sum[i];
            wire signed [15:0] branch_sum_hold = `WV_CORE.branch_sum_hold[i];
        end
        for (i = 0; i < 9; i = i + 1) begin : matrix_element
            wire signed [23:0] f_matrix = `WV_CORE.f_matrix[i];
            wire signed [23:0] matrix_temp = `WV_CORE.matrix_temp[i];
            wire signed [23:0] cov_post = `WV_CORE.cov_post[i];
            wire signed [23:0] cov_predict = `WV_CORE.cov_predict[i];
            wire signed [23:0] measurement_cov = `WV_CORE.measurement_cov[i];
            wire signed [23:0] normalized_cov = `WV_CORE.normalized_cov[i];
            wire signed [23:0] sign_cov = `WV_CORE.sign_cov[i];
            wire signed [23:0] cofactor = `WV_CORE.cofactor[i];
            wire signed [23:0] sign_cov_inverse = `WV_CORE.sign_cov_inverse[i];
            wire signed [23:0] gain = `WV_CORE.gain[i];
            wire signed [23:0] cov_correction = `WV_CORE.cov_correction[i];
        end
    endgenerate

    string capture_file;
    integer capture_debug_steps;
    integer capture_completed = 0;
    reg capture_enabled = 1'b0;
    initial begin
        if (!$value$plusargs("CAPTURE_FILE=%s", capture_file))
            $fatal(1, "CAPTURE_FILE is required");
        if (!$value$plusargs("CAPTURE_DEBUG_STEPS=%d", capture_debug_steps))
            capture_debug_steps = 0;
        $dumpfile(capture_file);
        if (capture_debug_steps > 0) begin
            $dumpvars(0, waveform_capture);
            $dumpvars(0, `WV_TB.dut);
        end else begin
            // Only interface, FSM and decoded posterior signals for 500 steps.
            $dumpvars(0, clk, rst_n, cfg_valid, cfg_ready, cfg_state_flat, cfg_cov_flat,
                input_valid, input_ready, f_input_flat, measurement_flat,
                threshold_valid, threshold_ready, threshold_flat,
                observation_valid, observation_ready, branch_observation_bits,
                result_valid, result_ready, state_out_flat, cov_out_flat,
                busy, done, overflow_flag, numeric_error, solver_error, fsm_state,
                state_x, state_y, state_z, cov_00, cov_11, cov_22);
        end
        capture_enabled = 1'b1;
    end

    // End debug recording after the Nth result handshake, not the simulation.
    // All original 500-step checks and CSV writes continue unchanged.
    always @(posedge clk) begin
        if (rst_n && result_valid && result_ready) begin
            capture_completed = capture_completed + 1;
            if (capture_enabled && capture_debug_steps > 0 &&
                capture_completed == capture_debug_steps) begin
                #1;
                $dumpoff;
                $dumpflush;
                capture_enabled = 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
