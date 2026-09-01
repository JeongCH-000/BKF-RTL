`timescale 1ns/1ps
`default_nettype none

// Public L=1 BKF top. The shared engine uses a single bit per feature.
module bkf_l1_core (
    input wire clk, input wire rst_n,
    input wire cfg_valid, output wire cfg_ready,
    input wire [71:0] cfg_state_flat, input wire [215:0] cfg_cov_flat,
    input wire model_valid, output wire model_ready, input wire [215:0] f_input_flat,
    output wire threshold_valid, input wire threshold_ready, output wire [71:0] threshold_flat,
    input wire observation_valid, output wire observation_ready, input wire [2:0] observation_bits,
    output wire result_valid, input wire result_ready,
    output wire [71:0] state_out_flat, output wire [215:0] cov_out_flat,
    output wire busy, output wire done, output wire overflow_flag,
    output wire numeric_error, output wire solver_error, output wire [5:0] fsm_state
);
    wire [215:0] unused_cov_predict;
    wire [215:0] unused_sign_cov;
    wire [215:0] unused_gain;
    wire signed [23:0] unused_determinant;
    wire [71:0] unused_reduced_observation;
    wire [47:0] unused_branch_sum;

    bkf_core #(.NUM_BRANCHES(1)) u_engine (
        .clk(clk), .rst_n(rst_n), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_state_flat(cfg_state_flat), .cfg_cov_flat(cfg_cov_flat),
        .model_valid(model_valid), .model_ready(model_ready), .f_input_flat(f_input_flat),
        .threshold_valid(threshold_valid), .threshold_ready(threshold_ready),
        .threshold_flat(threshold_flat), .observation_valid(observation_valid),
        .observation_ready(observation_ready), .observation_flat(observation_bits),
        .measurement_flat(72'd0),
        .result_valid(result_valid), .result_ready(result_ready),
        .state_out_flat(state_out_flat), .cov_out_flat(cov_out_flat),
        .busy(busy), .done(done), .overflow_flag(overflow_flag),
        .numeric_error(numeric_error), .solver_error(solver_error), .fsm_state(fsm_state),
        .debug_cov_predict_flat(unused_cov_predict), .debug_sign_cov_flat(unused_sign_cov),
        .debug_gain_flat(unused_gain), .debug_determinant(unused_determinant),
        .debug_reduced_observation_flat(unused_reduced_observation),
        .debug_branch_sum_flat(unused_branch_sum)
    );
endmodule

`default_nettype wire
