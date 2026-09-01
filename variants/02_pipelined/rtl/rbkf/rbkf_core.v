`timescale 1ns/1ps
`default_nettype none

// Reduced multi-branch BKF. Only three reduced feature statistics enter the
// filter engine; no 3L-by-3L matrix or replicated filter core is instantiated.
module rbkf_core #(
    parameter integer NUM_BRANCHES = 8
) (
    input wire clk, input wire rst_n,
    input wire cfg_valid, output wire cfg_ready,
    input wire [71:0] cfg_state_flat, input wire [215:0] cfg_cov_flat,
    input wire model_valid, output wire model_ready, input wire [215:0] f_input_flat,
    output wire threshold_valid, input wire threshold_ready, output wire [71:0] threshold_flat,
    input wire observation_valid, output wire observation_ready,
    input wire [(3*NUM_BRANCHES)-1:0] branch_observation_bits,
    output wire result_valid, input wire result_ready,
    output wire [71:0] state_out_flat, output wire [215:0] cov_out_flat,
    output wire busy, output wire done, output wire overflow_flag,
    output wire numeric_error, output wire solver_error, output wire [5:0] fsm_state
`ifdef WAVE_DEBUG
    ,
    output wire [71:0] debug_reduced_observation_flat,
    output wire [47:0] debug_branch_sum_flat,
    output wire [215:0] debug_reduced_cov_flat,
    output wire [215:0] debug_gain_flat,
    output wire signed [23:0] debug_determinant
`endif
);
    wire [215:0] unused_cov_predict;
    wire [71:0] debug_reduced_observation_int;
    wire [47:0] debug_branch_sum_int;
    wire [215:0] debug_reduced_cov_int;
    wire [215:0] debug_gain_int;
    wire signed [23:0] debug_determinant_int;

`ifdef WAVE_DEBUG
    assign debug_reduced_observation_flat = debug_reduced_observation_int;
    assign debug_branch_sum_flat = debug_branch_sum_int;
    assign debug_reduced_cov_flat = debug_reduced_cov_int;
    assign debug_gain_flat = debug_gain_int;
    assign debug_determinant = debug_determinant_int;
`endif

    bkf_core #(.NUM_BRANCHES(NUM_BRANCHES)) u_engine (
        .clk(clk), .rst_n(rst_n), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_state_flat(cfg_state_flat), .cfg_cov_flat(cfg_cov_flat),
        .model_valid(model_valid), .model_ready(model_ready), .f_input_flat(f_input_flat),
        .threshold_valid(threshold_valid), .threshold_ready(threshold_ready),
        .threshold_flat(threshold_flat), .observation_valid(observation_valid),
        .observation_ready(observation_ready), .observation_flat(branch_observation_bits),
        .measurement_flat(72'd0),
        .result_valid(result_valid), .result_ready(result_ready),
        .state_out_flat(state_out_flat), .cov_out_flat(cov_out_flat),
        .busy(busy), .done(done), .overflow_flag(overflow_flag),
        .numeric_error(numeric_error), .solver_error(solver_error), .fsm_state(fsm_state),
        .debug_cov_predict_flat(unused_cov_predict),
        .debug_sign_cov_flat(debug_reduced_cov_int), .debug_gain_flat(debug_gain_int),
        .debug_determinant(debug_determinant_int),
        .debug_reduced_observation_flat(debug_reduced_observation_int),
        .debug_branch_sum_flat(debug_branch_sum_int)
    );
endmodule

`default_nettype wire
