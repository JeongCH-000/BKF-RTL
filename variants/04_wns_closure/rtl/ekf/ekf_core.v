`timescale 1ns/1ps
`default_nettype none

// Ideal high-resolution EKF reference top (H=I3). The matrix/MAC/inverse
// engine is shared with BKF; Bussgang nonlinear stages are bypassed.
module ekf_core (
    input wire clk, input wire rst_n,
    input wire cfg_valid, output wire cfg_ready,
    input wire [71:0] cfg_state_flat, input wire [215:0] cfg_cov_flat,
    input wire input_valid, output wire input_ready,
    input wire [215:0] f_input_flat, input wire [71:0] measurement_flat,
    output wire result_valid, input wire result_ready,
    output wire [71:0] state_out_flat, output wire [215:0] cov_out_flat,
    output wire busy, output wire done, output wire overflow_flag,
    output wire numeric_error, output wire solver_error, output wire [5:0] fsm_state
`ifdef WAVE_DEBUG
    ,
    output wire [215:0] debug_cov_predict_flat,
    output wire [215:0] debug_innovation_cov_flat,
    output wire [215:0] debug_gain_flat,
    output wire [71:0] debug_innovation_flat,
    output wire signed [23:0] debug_determinant
`endif
);
    wire threshold_valid_unused;
    wire [71:0] threshold_unused;
    wire measurement_ready;
    wire [47:0] branch_sum_unused;
    wire [215:0] debug_cov_predict_int;
    wire [215:0] debug_innovation_cov_int;
    wire [215:0] debug_gain_int;
    wire [71:0] debug_innovation_int;
    wire signed [23:0] debug_determinant_int;

`ifdef WAVE_DEBUG
    assign debug_cov_predict_flat = debug_cov_predict_int;
    assign debug_innovation_cov_flat = debug_innovation_cov_int;
    assign debug_gain_flat = debug_gain_int;
    assign debug_innovation_flat = debug_innovation_int;
    assign debug_determinant = debug_determinant_int;
`endif

    bkf_core #(.NUM_BRANCHES(1), .EKF_MODE(1)) u_engine (
        .clk(clk), .rst_n(rst_n), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_state_flat(cfg_state_flat), .cfg_cov_flat(cfg_cov_flat),
        .model_valid(input_valid), .model_ready(input_ready), .f_input_flat(f_input_flat),
        .threshold_valid(threshold_valid_unused), .threshold_ready(1'b1),
        .threshold_flat(threshold_unused), .observation_valid(1'b0),
        .observation_ready(measurement_ready), .observation_flat(3'b000),
        .measurement_flat(measurement_flat),
        .result_valid(result_valid), .result_ready(result_ready),
        .state_out_flat(state_out_flat), .cov_out_flat(cov_out_flat),
        .busy(busy), .done(done), .overflow_flag(overflow_flag),
        .numeric_error(numeric_error), .solver_error(solver_error), .fsm_state(fsm_state),
        .debug_cov_predict_flat(debug_cov_predict_int),
        .debug_sign_cov_flat(debug_innovation_cov_int), .debug_gain_flat(debug_gain_int),
        .debug_determinant(debug_determinant_int),
        .debug_reduced_observation_flat(debug_innovation_int),
        .debug_branch_sum_flat(branch_sum_unused)
    );
endmodule

`default_nettype wire
