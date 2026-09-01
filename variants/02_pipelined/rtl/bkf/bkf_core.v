`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Fixed-dimension Bussgang-aided Kalman filter accelerator.
// All flattened matrices are row-major with element zero in the least-significant bits.
module bkf_core #(
    parameter integer NUM_BRANCHES = 1,
    parameter integer EKF_MODE = 0
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    cfg_valid,
    output wire                    cfg_ready,
    input  wire [71:0]             cfg_state_flat,
    input  wire [215:0]            cfg_cov_flat,

    input  wire                    model_valid,
    output wire                    model_ready,
    input  wire [215:0]            f_input_flat,

    output wire                    threshold_valid,
    input  wire                    threshold_ready,
    output wire [71:0]             threshold_flat,

    input  wire                    observation_valid,
    output wire                    observation_ready,
    // Branch-major order: bit (branch*3 + feature). 1=+1, 0=-1.
    input  wire [(3*NUM_BRANCHES)-1:0] observation_flat,
    input  wire [71:0]             measurement_flat,

    output wire                    result_valid,
    input  wire                    result_ready,
    output wire [71:0]             state_out_flat,
    output wire [215:0]            cov_out_flat,

    output wire                    busy,
    output wire                    done,
    output reg                     overflow_flag,
    output reg                     numeric_error,
    output reg                     solver_error,
    output wire [5:0]              fsm_state,

    output wire [215:0]            debug_cov_predict_flat,
    output wire [215:0]            debug_sign_cov_flat,
    output wire [215:0]            debug_gain_flat,
    output wire signed [23:0]      debug_determinant,
    output wire [71:0]             debug_reduced_observation_flat,
    output wire [47:0]             debug_branch_sum_flat
);

    localparam signed [23:0] FX_ONE     = 24'sd65536;
    localparam signed [23:0] FX_NEG_ONE = -24'sd65536;
    localparam signed [23:0] Q_DIAG     = 24'sd66;      // 0.001
    localparam signed [23:0] R_DIAG     = 24'sd6554;    // 0.1
    localparam signed [23:0] ALPHA      = 24'sd52290;   // \sqrt{2/\pi}
    localparam signed [23:0] DET_FLOOR  = 24'sd64;
    localparam signed [23:0] FX_MAX     = 24'sh7fffff;
    localparam signed [23:0] FX_MIN     = 24'sh800000;

    localparam [5:0] ST_IDLE          = 6'd0;
    localparam [5:0] ST_XPRED         = 6'd1;
    localparam [5:0] ST_COV_INNER     = 6'd2;
    localparam [5:0] ST_COV_OUTER     = 6'd3;
    localparam [5:0] ST_ADD_Q         = 6'd4;
    localparam [5:0] ST_SYM_SIG       = 6'd5;
    localparam [5:0] ST_THRESHOLD     = 6'd6;
    localparam [5:0] ST_WAIT_OBS      = 6'd7;
    localparam [5:0] ST_P_BUILD       = 6'd8;
    localparam [5:0] ST_P_SYM         = 6'd9;
    localparam [5:0] ST_RSQRT_REQ     = 6'd10;
    localparam [5:0] ST_RSQRT_WAIT    = 6'd11;
    localparam [5:0] ST_PNORM_M1      = 6'd12;
    localparam [5:0] ST_PNORM_M2      = 6'd13;
    localparam [5:0] ST_ASIN_REQ      = 6'd14;
    localparam [5:0] ST_ASIN_WAIT     = 6'd15;
    localparam [5:0] ST_S_SYM         = 6'd16;
    localparam [5:0] ST_B_CALC        = 6'd17;
    localparam [5:0] ST_COF_P1        = 6'd18;
    localparam [5:0] ST_COF_P2        = 6'd19;
    localparam [5:0] ST_DET           = 6'd20;
    localparam [5:0] ST_INV_DIV       = 6'd21;
    localparam [5:0] ST_GAIN_INNER    = 6'd22;
    localparam [5:0] ST_GAIN          = 6'd23;
    localparam [5:0] ST_X_MV          = 6'd24;
    localparam [5:0] ST_X_ADD         = 6'd25;
    localparam [5:0] ST_COV_UP_INNER  = 6'd26;
    localparam [5:0] ST_COV_CORR      = 6'd27;
    localparam [5:0] ST_COV_SUB       = 6'd28;
    localparam [5:0] ST_RESULT        = 6'd29;
    localparam [5:0] ST_INV_WAIT      = 6'd30;
    localparam [5:0] ST_SELF_M1       = 6'd31;
    localparam [5:0] ST_SELF_M2       = 6'd32;
    localparam [5:0] ST_SELF_ASIN_REQ = 6'd33;
    localparam [5:0] ST_SELF_ASIN_WAIT= 6'd34;
    localparam [5:0] ST_SELF_REDUCE   = 6'd35;
    localparam [5:0] ST_EKF_S_COPY    = 6'd36;
    localparam [5:0] ST_POST_SYM      = 6'd37;

    reg [5:0] state;
    reg       configured;
    reg [1:0] row_index;
    reg [1:0] col_index;
    reg [1:0] dot_index;
    reg [3:0] element_index;

    reg signed [23:0] state_post [0:2];
    reg signed [23:0] cov_post [0:8];
    reg signed [23:0] f_matrix [0:8];
    reg signed [23:0] state_predict [0:2];
    reg signed [23:0] measurement_hold [0:2];
    reg signed [23:0] matrix_temp [0:8];
    reg signed [23:0] cov_predict [0:8];
    reg signed [23:0] measurement_cov [0:8];
    reg signed [23:0] diag_rsqrt [0:2];
    reg signed [23:0] normalized_cov [0:8];
    reg signed [23:0] sign_cov_pre [0:8];
    reg signed [23:0] sign_cov [0:8];
    reg signed [23:0] self_normalized [0:2];
    reg signed [23:0] b_diag [0:2];
    reg signed [23:0] cofactor [0:8];
    reg signed [23:0] sign_cov_inverse [0:8];
    reg signed [23:0] gain_inner [0:8];
    reg signed [23:0] gain [0:8];
    reg signed [23:0] observation_q [0:2];
    reg signed [23:0] state_correction [0:2];
    reg signed [23:0] cov_update_inner [0:8];
    reg signed [23:0] cov_correction [0:8];
    reg signed [23:0] determinant;
    reg signed [23:0] scalar_temp;
    reg signed [49:0] mac_accumulator;
    reg signed [15:0] branch_sum [0:2];

    reg signed [23:0] mul_a;
    reg signed [23:0] mul_b;
    reg signed [23:0] cofactor_a1;
    reg signed [23:0] cofactor_b1;
    reg signed [23:0] cofactor_a2;
    reg signed [23:0] cofactor_b2;
    reg signed [23:0] cofactor_transposed;
    reg signed [23:0] pair_left;
    reg signed [23:0] pair_right;

    wire               mul_request_valid;
    wire               mul_request_ready;
    wire               pipe_result_valid;
    wire               pipe_result_ready;
    wire signed [23:0] pipe_rounded_product;
    wire signed [49:0] pipe_mac_sum;
    wire signed [23:0] pipe_rounded_mac;
    wire               pipe_product_overflow;
    wire               pipe_mac_overflow;
    wire [5:0]         pipe_result_operation;
    wire [3:0]         pipe_result_element_index;
    wire [1:0]         pipe_result_row_index;
    wire [1:0]         pipe_result_col_index;
    wire [1:0]         pipe_result_dot_index;
    wire               pipeline_stage1_valid;
    wire               pipeline_stage2_valid;
    wire               pipeline_stage3_valid;

    wire               rsqrt_en;
    reg signed [23:0]  rsqrt_x;
    wire signed [23:0] rsqrt_y;
    wire               rsqrt_valid;
    wire               rsqrt_domain_error;

    wire               asin_en;
    reg signed [23:0]  asin_x;
    wire signed [23:0] asin_y;
    wire               asin_valid;
    wire               asin_domain_error;

    wire               divider_start;
    wire               divider_busy;
    wire               divider_valid;
    wire signed [23:0] divider_quotient;
    wire               divider_by_zero;
    wire               divider_overflow;

    integer reset_index;
    integer load_index;
    integer branch_index;
    integer feature_index;

    `include "rtl/common/fx_q8_16_functions.vh"

    function [1:0] matrix_row;
        input [3:0] flat_index;
        begin
            case (flat_index)
                4'd0, 4'd1, 4'd2: matrix_row = 2'd0;
                4'd3, 4'd4, 4'd5: matrix_row = 2'd1;
                default: matrix_row = 2'd2;
            endcase
        end
    endfunction

    function [1:0] matrix_col;
        input [3:0] flat_index;
        begin
            case (flat_index)
                4'd0, 4'd3, 4'd6: matrix_col = 2'd0;
                4'd1, 4'd4, 4'd7: matrix_col = 2'd1;
                default: matrix_col = 2'd2;
            endcase
        end
    endfunction

    function signed [23:0] branch_average_q16;
        input signed [15:0] sum;
        reg signed [31:0] scaled;
        begin
            scaled = {{16{sum[15]}}, sum};
            if (NUM_BRANCHES == 1)
                branch_average_q16 = (scaled <<< 16);
            else if (NUM_BRANCHES == 8)
                branch_average_q16 = (scaled <<< 13);
            else
                branch_average_q16 = 24'sd0;
        end
    endfunction

    function signed [23:0] reduce_self_cov_l8;
        input signed [23:0] cross_branch_cov;
        reg signed [31:0] wide_sum;
        reg signed [31:0] rounded;
        begin
            wide_sum = 32'sd65536 + ({{8{cross_branch_cov[23]}}, cross_branch_cov} <<< 3)
                       - {{8{cross_branch_cov[23]}}, cross_branch_cov};
            if (wide_sum < 0)
                rounded = -(((-wide_sum) + 32'sd4) >>> 3);
            else
                rounded = (wide_sum + 32'sd4) >>> 3;
            reduce_self_cov_l8 = rounded[23:0];
        end
    endfunction

    assign mul_request_valid =
        (state == ST_XPRED) ||
        (state == ST_COV_INNER) ||
        (state == ST_COV_OUTER) ||
        ((state == ST_PNORM_M1) && (element_index != 4'd0) &&
         (element_index != 4'd4) && (element_index != 4'd8)) ||
        (state == ST_PNORM_M2) ||
        (state == ST_B_CALC) ||
        (state == ST_SELF_M1) ||
        (state == ST_SELF_M2) ||
        (state == ST_COF_P1) ||
        (state == ST_COF_P2) ||
        (state == ST_DET) ||
        (state == ST_GAIN_INNER) ||
        (state == ST_GAIN) ||
        (state == ST_X_MV) ||
        (state == ST_COV_UP_INNER) ||
        (state == ST_COV_CORR);
    assign pipe_result_ready = pipe_result_valid && (pipe_result_operation == state);
    assign divider_start = (state == ST_INV_DIV);

    assign cfg_ready = (state == ST_IDLE);
    assign model_ready = (state == ST_IDLE) && configured && !cfg_valid;
    assign threshold_valid = (state == ST_THRESHOLD) && (EKF_MODE == 0);
    assign observation_ready = (state == ST_WAIT_OBS);
    assign result_valid = (state == ST_RESULT);
    assign busy = (state != ST_IDLE);
    assign done = result_valid && result_ready;
    assign fsm_state = state;
    assign debug_determinant = determinant;
    assign debug_reduced_observation_flat[23:0] = observation_q[0];
    assign debug_reduced_observation_flat[47:24] = observation_q[1];
    assign debug_reduced_observation_flat[71:48] = observation_q[2];
    assign debug_branch_sum_flat[15:0] = branch_sum[0];
    assign debug_branch_sum_flat[31:16] = branch_sum[1];
    assign debug_branch_sum_flat[47:32] = branch_sum[2];

    genvar state_gen;
    generate
        for (state_gen = 0; state_gen < 3; state_gen = state_gen + 1) begin : PACK_STATE
            assign threshold_flat[(state_gen*24) +: 24] = state_predict[state_gen];
            assign state_out_flat[(state_gen*24) +: 24] = state_post[state_gen];
        end
    endgenerate

    genvar matrix_gen;
    generate
        for (matrix_gen = 0; matrix_gen < 9; matrix_gen = matrix_gen + 1) begin : PACK_MATRIX
            assign cov_out_flat[(matrix_gen*24) +: 24] = cov_post[matrix_gen];
            assign debug_cov_predict_flat[(matrix_gen*24) +: 24] = cov_predict[matrix_gen];
            assign debug_sign_cov_flat[(matrix_gen*24) +: 24] = sign_cov[matrix_gen];
            assign debug_gain_flat[(matrix_gen*24) +: 24] = gain[matrix_gen];
        end
    endgenerate

    assign rsqrt_en = (state == ST_RSQRT_REQ);
    assign asin_en = (state == ST_ASIN_REQ) || (state == ST_SELF_ASIN_REQ);

    q8_16_rsqrt_lut u_rsqrt_lut (
        .clk(clk),
        .en(rsqrt_en),
        .x(rsqrt_x),
        .y(rsqrt_y),
        .valid(rsqrt_valid),
        .domain_error(rsqrt_domain_error)
    );

    arcsine_cov_lut_q8_16 u_arcsine_cov_lut (
        .clk(clk),
        .en(asin_en),
        .x(asin_x),
        .y(asin_y),
        .valid(asin_valid),
        .domain_error(asin_domain_error)
    );

    fx_divider_q8_16 u_divider (
        .clk(clk),
        .rst_n(rst_n),
        .start(divider_start),
        .numerator(cofactor_transposed),
        .denominator(determinant),
        .busy(divider_busy),
        .valid(divider_valid),
        .quotient(divider_quotient),
        .divide_by_zero(divider_by_zero),
        .overflow(divider_overflow)
    );

    fx_mul_mac_pipeline u_mul_mac_pipeline (
        .clk(clk),
        .rst_n(rst_n),
        .request_valid(mul_request_valid),
        .request_ready(mul_request_ready),
        .request_operand_a(mul_a),
        .request_operand_b(mul_b),
        .request_accumulator(mac_accumulator),
        .request_operation(state),
        .request_element_index(element_index),
        .request_row_index(row_index),
        .request_col_index(col_index),
        .request_dot_index(dot_index),
        .result_valid(pipe_result_valid),
        .result_ready(pipe_result_ready),
        .result_rounded_product(pipe_rounded_product),
        .result_mac_sum(pipe_mac_sum),
        .result_rounded_mac(pipe_rounded_mac),
        .result_product_overflow(pipe_product_overflow),
        .result_mac_overflow(pipe_mac_overflow),
        .result_operation(pipe_result_operation),
        .result_element_index(pipe_result_element_index),
        .result_row_index(pipe_result_row_index),
        .result_col_index(pipe_result_col_index),
        .result_dot_index(pipe_result_dot_index),
        .stage1_valid(pipeline_stage1_valid),
        .stage2_valid(pipeline_stage2_valid),
        .stage3_valid(pipeline_stage3_valid)
    );

    always @* begin
        for (feature_index = 0; feature_index < 3; feature_index = feature_index + 1) begin
            branch_sum[feature_index] = 16'sd0;
            for (branch_index = 0; branch_index < NUM_BRANCHES; branch_index = branch_index + 1) begin
                if (observation_flat[(branch_index*3)+feature_index])
                    branch_sum[feature_index] = branch_sum[feature_index] + 16'sd1;
                else
                    branch_sum[feature_index] = branch_sum[feature_index] - 16'sd1;
            end
        end
    end

    always @* begin
        case (element_index)
            4'd0: begin pair_left = cov_predict[1]; pair_right = cov_predict[3]; end
            4'd1: begin pair_left = cov_predict[2]; pair_right = cov_predict[6]; end
            default: begin pair_left = cov_predict[5]; pair_right = cov_predict[7]; end
        endcase
        if (state == ST_P_SYM) begin
            case (element_index)
                4'd0: begin pair_left = measurement_cov[1]; pair_right = measurement_cov[3]; end
                4'd1: begin pair_left = measurement_cov[2]; pair_right = measurement_cov[6]; end
                default: begin pair_left = measurement_cov[5]; pair_right = measurement_cov[7]; end
            endcase
        end else if (state == ST_S_SYM) begin
            case (element_index)
                4'd0: begin pair_left = sign_cov_pre[1]; pair_right = sign_cov_pre[3]; end
                4'd1: begin pair_left = sign_cov_pre[2]; pair_right = sign_cov_pre[6]; end
                default: begin pair_left = sign_cov_pre[5]; pair_right = sign_cov_pre[7]; end
            endcase
        end else if (state == ST_POST_SYM) begin
            case (element_index)
                4'd0: begin pair_left = cov_post[1]; pair_right = cov_post[3]; end
                4'd1: begin pair_left = cov_post[2]; pair_right = cov_post[6]; end
                default: begin pair_left = cov_post[5]; pair_right = cov_post[7]; end
            endcase
        end
    end

    always @* begin
        cofactor_a1 = 24'sd0;
        cofactor_b1 = 24'sd0;
        cofactor_a2 = 24'sd0;
        cofactor_b2 = 24'sd0;
        case (element_index)
            4'd0: begin cofactor_a1=sign_cov[4]; cofactor_b1=sign_cov[8]; cofactor_a2=sign_cov[5]; cofactor_b2=sign_cov[7]; end
            4'd1: begin cofactor_a1=sign_cov[5]; cofactor_b1=sign_cov[6]; cofactor_a2=sign_cov[3]; cofactor_b2=sign_cov[8]; end
            4'd2: begin cofactor_a1=sign_cov[3]; cofactor_b1=sign_cov[7]; cofactor_a2=sign_cov[4]; cofactor_b2=sign_cov[6]; end
            4'd3: begin cofactor_a1=sign_cov[2]; cofactor_b1=sign_cov[7]; cofactor_a2=sign_cov[1]; cofactor_b2=sign_cov[8]; end
            4'd4: begin cofactor_a1=sign_cov[0]; cofactor_b1=sign_cov[8]; cofactor_a2=sign_cov[2]; cofactor_b2=sign_cov[6]; end
            4'd5: begin cofactor_a1=sign_cov[1]; cofactor_b1=sign_cov[6]; cofactor_a2=sign_cov[0]; cofactor_b2=sign_cov[7]; end
            4'd6: begin cofactor_a1=sign_cov[1]; cofactor_b1=sign_cov[5]; cofactor_a2=sign_cov[2]; cofactor_b2=sign_cov[4]; end
            4'd7: begin cofactor_a1=sign_cov[2]; cofactor_b1=sign_cov[3]; cofactor_a2=sign_cov[0]; cofactor_b2=sign_cov[5]; end
            default: begin cofactor_a1=sign_cov[0]; cofactor_b1=sign_cov[4]; cofactor_a2=sign_cov[1]; cofactor_b2=sign_cov[3]; end
        endcase
    end

    always @* begin
        case (element_index)
            4'd0: cofactor_transposed = cofactor[0];
            4'd1: cofactor_transposed = cofactor[3];
            4'd2: cofactor_transposed = cofactor[6];
            4'd3: cofactor_transposed = cofactor[1];
            4'd4: cofactor_transposed = cofactor[4];
            4'd5: cofactor_transposed = cofactor[7];
            4'd6: cofactor_transposed = cofactor[2];
            4'd7: cofactor_transposed = cofactor[5];
            default: cofactor_transposed = cofactor[8];
        endcase
    end

    always @* begin
        rsqrt_x = 24'sd0;
        case (element_index)
            4'd0: rsqrt_x = measurement_cov[0];
            4'd1: rsqrt_x = measurement_cov[4];
            default: rsqrt_x = measurement_cov[8];
        endcase
        if (state == ST_SELF_ASIN_REQ)
            asin_x = self_normalized[element_index];
        else
            asin_x = normalized_cov[element_index];
    end

    always @* begin
        mul_a = 24'sd0;
        mul_b = 24'sd0;
        case (state)
            ST_XPRED: begin
                mul_a = f_matrix[(row_index*3)+dot_index];
                mul_b = state_post[dot_index];
            end
            ST_COV_INNER: begin
                mul_a = cov_post[(row_index*3)+dot_index];
                mul_b = f_matrix[(col_index*3)+dot_index];
            end
            ST_COV_OUTER: begin
                mul_a = f_matrix[(row_index*3)+dot_index];
                mul_b = matrix_temp[(dot_index*3)+col_index];
            end
            ST_PNORM_M1: begin
                mul_a = measurement_cov[element_index];
                mul_b = diag_rsqrt[matrix_row(element_index)];
            end
            ST_PNORM_M2: begin
                mul_a = scalar_temp;
                mul_b = diag_rsqrt[matrix_col(element_index)];
            end
            ST_B_CALC: begin
                mul_a = ALPHA;
                mul_b = diag_rsqrt[element_index];
            end
            ST_SELF_M1: begin
                case (element_index)
                    4'd0: mul_a = cov_predict[0];
                    4'd1: mul_a = cov_predict[4];
                    default: mul_a = cov_predict[8];
                endcase
                mul_b = diag_rsqrt[element_index];
            end
            ST_SELF_M2: begin
                mul_a = scalar_temp;
                mul_b = diag_rsqrt[element_index];
            end
            ST_COF_P1: begin
                mul_a = cofactor_a1;
                mul_b = cofactor_b1;
            end
            ST_COF_P2: begin
                mul_a = cofactor_a2;
                mul_b = cofactor_b2;
            end
            ST_DET: begin
                mul_a = sign_cov[dot_index];
                mul_b = cofactor[dot_index];
            end
            ST_GAIN_INNER: begin
                mul_a = b_diag[matrix_row(element_index)];
                mul_b = sign_cov_inverse[element_index];
            end
            ST_GAIN: begin
                mul_a = cov_predict[(row_index*3)+dot_index];
                mul_b = gain_inner[(dot_index*3)+col_index];
            end
            ST_X_MV: begin
                mul_a = gain[(row_index*3)+dot_index];
                mul_b = observation_q[dot_index];
            end
            ST_COV_UP_INNER: begin
                mul_a = sign_cov[(row_index*3)+dot_index];
                mul_b = gain[(col_index*3)+dot_index];
            end
            ST_COV_CORR: begin
                mul_a = gain[(row_index*3)+dot_index];
                mul_b = cov_update_inner[(dot_index*3)+col_index];
            end
            default: begin
                mul_a = 24'sd0;
                mul_b = 24'sd0;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            configured <= 1'b0;
            row_index <= 2'd0;
            col_index <= 2'd0;
            dot_index <= 2'd0;
            element_index <= 4'd0;
            determinant <= 24'sd0;
            scalar_temp <= 24'sd0;
            mac_accumulator <= 50'sd0;
            overflow_flag <= 1'b0;
            numeric_error <= 1'b0;
            solver_error <= 1'b0;
            for (reset_index = 0; reset_index < 3; reset_index = reset_index + 1) begin
                state_post[reset_index] <= 24'sd0;
                state_predict[reset_index] <= 24'sd0;
                measurement_hold[reset_index] <= 24'sd0;
                diag_rsqrt[reset_index] <= 24'sd0;
                b_diag[reset_index] <= 24'sd0;
                self_normalized[reset_index] <= 24'sd0;
                observation_q[reset_index] <= 24'sd0;
                state_correction[reset_index] <= 24'sd0;
            end
            for (reset_index = 0; reset_index < 9; reset_index = reset_index + 1) begin
                cov_post[reset_index] <= 24'sd0;
                f_matrix[reset_index] <= 24'sd0;
                matrix_temp[reset_index] <= 24'sd0;
                cov_predict[reset_index] <= 24'sd0;
                measurement_cov[reset_index] <= 24'sd0;
                normalized_cov[reset_index] <= 24'sd0;
                sign_cov_pre[reset_index] <= 24'sd0;
                sign_cov[reset_index] <= 24'sd0;
                cofactor[reset_index] <= 24'sd0;
                sign_cov_inverse[reset_index] <= 24'sd0;
                gain_inner[reset_index] <= 24'sd0;
                gain[reset_index] <= 24'sd0;
                cov_update_inner[reset_index] <= 24'sd0;
                cov_correction[reset_index] <= 24'sd0;
            end
        end else begin
            case (state)
                ST_IDLE: begin
                    if (cfg_valid) begin
                        for (load_index = 0; load_index < 3; load_index = load_index + 1)
                            state_post[load_index] <= $signed(cfg_state_flat[(load_index*24) +: 24]);
                        for (load_index = 0; load_index < 9; load_index = load_index + 1)
                            cov_post[load_index] <= $signed(cfg_cov_flat[(load_index*24) +: 24]);
                        configured <= 1'b1;
                        overflow_flag <= 1'b0;
                        numeric_error <= 1'b0;
                        solver_error <= 1'b0;
                    end else if (model_valid && configured) begin
                        for (load_index = 0; load_index < 9; load_index = load_index + 1)
                            f_matrix[load_index] <= $signed(f_input_flat[(load_index*24) +: 24]);
                        for (load_index = 0; load_index < 3; load_index = load_index + 1)
                            measurement_hold[load_index] <= $signed(measurement_flat[(load_index*24) +: 24]);
                        row_index <= 2'd0;
                        col_index <= 2'd0;
                        dot_index <= 2'd0;
                        mac_accumulator <= 50'sd0;
                        overflow_flag <= 1'b0;
                        numeric_error <= 1'b0;
                        solver_error <= 1'b0;
                        state <= ST_XPRED;
                    end
                end

                ST_XPRED: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_XPRED)) begin
                        if (pipe_result_dot_index == 2'd0) begin
                            mac_accumulator <= pipe_mac_sum;
                            dot_index <= 2'd1;
                        end else if (pipe_result_dot_index == 2'd1) begin
                            mac_accumulator <= pipe_mac_sum;
                            dot_index <= 2'd2;
                        end else begin
                            state_predict[pipe_result_row_index] <= pipe_rounded_mac;
                            if (pipe_mac_overflow) overflow_flag <= 1'b1;
                            dot_index <= 2'd0;
                            mac_accumulator <= 50'sd0;
                            if (pipe_result_row_index == 2'd2) begin
                                row_index <= 2'd0;
                                col_index <= 2'd0;
                                state <= ST_COV_INNER;
                            end else begin
                                row_index <= pipe_result_row_index + 2'd1;
                            end
                        end
                    end
                end

                ST_COV_INNER, ST_COV_OUTER, ST_GAIN, ST_COV_UP_INNER, ST_COV_CORR: begin
                    if (pipe_result_valid && (pipe_result_operation == state)) begin
                        if (pipe_result_dot_index == 2'd0) begin
                            mac_accumulator <= pipe_mac_sum;
                            dot_index <= 2'd1;
                        end else if (pipe_result_dot_index == 2'd1) begin
                            mac_accumulator <= pipe_mac_sum;
                            dot_index <= 2'd2;
                        end else begin
                            if (state == ST_COV_INNER)
                                matrix_temp[(pipe_result_row_index*3)+pipe_result_col_index] <= pipe_rounded_mac;
                            else if (state == ST_COV_OUTER)
                                cov_predict[(pipe_result_row_index*3)+pipe_result_col_index] <= pipe_rounded_mac;
                            else if (state == ST_GAIN)
                                gain[(pipe_result_row_index*3)+pipe_result_col_index] <= pipe_rounded_mac;
                            else if (state == ST_COV_UP_INNER)
                                cov_update_inner[(pipe_result_row_index*3)+pipe_result_col_index] <= pipe_rounded_mac;
                            else
                                cov_correction[(pipe_result_row_index*3)+pipe_result_col_index] <= pipe_rounded_mac;
                            if (pipe_mac_overflow) overflow_flag <= 1'b1;
                            dot_index <= 2'd0;
                            mac_accumulator <= 50'sd0;
                            if (pipe_result_col_index == 2'd2) begin
                                col_index <= 2'd0;
                                if (pipe_result_row_index == 2'd2) begin
                                    row_index <= 2'd0;
                                    if (state == ST_COV_INNER)
                                        state <= ST_COV_OUTER;
                                    else if (state == ST_COV_OUTER) begin
                                        element_index <= 4'd0;
                                        state <= ST_ADD_Q;
                                    end else if (state == ST_GAIN) begin
                                        dot_index <= 2'd0;
                                        state <= ST_X_MV;
                                    end else if (state == ST_COV_UP_INNER)
                                        state <= ST_COV_CORR;
                                    else begin
                                        element_index <= 4'd0;
                                        state <= ST_COV_SUB;
                                    end
                                end else begin
                                    row_index <= pipe_result_row_index + 2'd1;
                                end
                            end else begin
                                col_index <= pipe_result_col_index + 2'd1;
                            end
                        end
                    end
                end

                ST_ADD_Q: begin
                    if ((element_index == 4'd0) || (element_index == 4'd4) || (element_index == 4'd8)) begin
                        cov_predict[element_index] <= add_sat24(cov_predict[element_index], Q_DIAG);
                        if (add_overflow24(cov_predict[element_index], Q_DIAG)) overflow_flag <= 1'b1;
                    end
                    if (element_index == 4'd8) begin
                        element_index <= 4'd0;
                        state <= ST_SYM_SIG;
                    end else begin
                        element_index <= element_index + 4'd1;
                    end
                end

                ST_SYM_SIG: begin
                    if (element_index == 4'd0) begin
                        cov_predict[1] <= average24(pair_left, pair_right);
                        cov_predict[3] <= average24(pair_left, pair_right);
                    end else if (element_index == 4'd1) begin
                        cov_predict[2] <= average24(pair_left, pair_right);
                        cov_predict[6] <= average24(pair_left, pair_right);
                    end else begin
                        cov_predict[5] <= average24(pair_left, pair_right);
                        cov_predict[7] <= average24(pair_left, pair_right);
                    end
                    if (element_index == 4'd2) begin
                        element_index <= 4'd0;
                        if (EKF_MODE != 0)
                            state <= ST_WAIT_OBS;
                        else
                            state <= ST_THRESHOLD;
                    end else begin
                        element_index <= element_index + 4'd1;
                    end
                end

                ST_THRESHOLD: begin
                    if (threshold_ready)
                        state <= ST_WAIT_OBS;
                end

                ST_WAIT_OBS: begin
                    if ((EKF_MODE != 0) || observation_valid) begin
                        for (load_index = 0; load_index < 3; load_index = load_index + 1) begin
                            if (EKF_MODE != 0) begin
                                observation_q[load_index] <= sub_sat24(
                                    measurement_hold[load_index],
                                    state_predict[load_index]);
                                if (sub_overflow24(
                                    measurement_hold[load_index],
                                    state_predict[load_index]))
                                    overflow_flag <= 1'b1;
                            end else begin
                                observation_q[load_index] <= branch_average_q16(branch_sum[load_index]);
                            end
                        end
                        if ((EKF_MODE == 0) && (NUM_BRANCHES != 1) && (NUM_BRANCHES != 8))
                            numeric_error <= 1'b1;
                        element_index <= 4'd0;
                        state <= ST_P_BUILD;
                    end
                end

                ST_P_BUILD: begin
                    if ((element_index == 4'd0) || (element_index == 4'd4) || (element_index == 4'd8)) begin
                        measurement_cov[element_index] <= add_sat24(cov_predict[element_index], R_DIAG);
                        if (add_overflow24(cov_predict[element_index], R_DIAG)) overflow_flag <= 1'b1;
                    end else begin
                        measurement_cov[element_index] <= cov_predict[element_index];
                    end
                    if (element_index == 4'd8) begin
                        element_index <= 4'd0;
                        state <= ST_P_SYM;
                    end else begin
                        element_index <= element_index + 4'd1;
                    end
                end

                ST_P_SYM: begin
                    if (element_index == 4'd0) begin
                        measurement_cov[1] <= average24(pair_left, pair_right);
                        measurement_cov[3] <= average24(pair_left, pair_right);
                    end else if (element_index == 4'd1) begin
                        measurement_cov[2] <= average24(pair_left, pair_right);
                        measurement_cov[6] <= average24(pair_left, pair_right);
                    end else begin
                        measurement_cov[5] <= average24(pair_left, pair_right);
                        measurement_cov[7] <= average24(pair_left, pair_right);
                    end
                    if (element_index == 4'd2) begin
                        element_index <= 4'd0;
                        if (EKF_MODE != 0)
                            state <= ST_EKF_S_COPY;
                        else
                            state <= ST_RSQRT_REQ;
                    end else begin
                        element_index <= element_index + 4'd1;
                    end
                end

                ST_RSQRT_REQ: state <= ST_RSQRT_WAIT;

                ST_RSQRT_WAIT: begin
                    if (rsqrt_valid) begin
                        diag_rsqrt[element_index] <= rsqrt_y;
                        if (rsqrt_domain_error) numeric_error <= 1'b1;
                        if (element_index == 4'd2) begin
                            element_index <= 4'd0;
                            state <= ST_PNORM_M1;
                        end else begin
                            element_index <= element_index + 4'd1;
                            state <= ST_RSQRT_REQ;
                        end
                    end
                end

                ST_PNORM_M1: begin
                    if ((element_index == 4'd0) || (element_index == 4'd4) || (element_index == 4'd8)) begin
                        normalized_cov[element_index] <= FX_ONE;
                        if (element_index == 4'd8) begin
                            element_index <= 4'd0;
                            state <= ST_ASIN_REQ;
                        end else begin
                            element_index <= element_index + 4'd1;
                        end
                    end else if (pipe_result_valid && (pipe_result_operation == ST_PNORM_M1)) begin
                        scalar_temp <= pipe_rounded_product;
                        if (pipe_product_overflow) overflow_flag <= 1'b1;
                        element_index <= pipe_result_element_index;
                        state <= ST_PNORM_M2;
                    end
                end

                ST_PNORM_M2: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_PNORM_M2)) begin
                        if ($signed(pipe_rounded_product) > $signed(FX_ONE)) begin
                            normalized_cov[pipe_result_element_index] <= FX_ONE;
                            numeric_error <= 1'b1;
                        end else if ($signed(pipe_rounded_product) < $signed(FX_NEG_ONE)) begin
                            normalized_cov[pipe_result_element_index] <= FX_NEG_ONE;
                            numeric_error <= 1'b1;
                        end else begin
                            normalized_cov[pipe_result_element_index] <= pipe_rounded_product;
                        end
                        if (pipe_product_overflow) overflow_flag <= 1'b1;
                        if (pipe_result_element_index == 4'd8) begin
                            element_index <= 4'd0;
                            state <= ST_ASIN_REQ;
                        end else begin
                            element_index <= pipe_result_element_index + 4'd1;
                            state <= ST_PNORM_M1;
                        end
                    end
                end

                ST_ASIN_REQ: state <= ST_ASIN_WAIT;

                ST_ASIN_WAIT: begin
                    if (asin_valid) begin
                        if ((element_index == 4'd0) || (element_index == 4'd4) || (element_index == 4'd8))
                            sign_cov_pre[element_index] <= FX_ONE;
                        else
                            sign_cov_pre[element_index] <= asin_y;
                        if (asin_domain_error) numeric_error <= 1'b1;
                        if (element_index == 4'd8) begin
                            element_index <= 4'd0;
                            state <= ST_S_SYM;
                        end else begin
                            element_index <= element_index + 4'd1;
                            state <= ST_ASIN_REQ;
                        end
                    end
                end

                ST_S_SYM: begin
                    if (element_index == 4'd0) begin
                        sign_cov[0] <= FX_ONE;
                        sign_cov[4] <= FX_ONE;
                        sign_cov[8] <= FX_ONE;
                        sign_cov[1] <= average24(pair_left, pair_right);
                        sign_cov[3] <= average24(pair_left, pair_right);
                    end else if (element_index == 4'd1) begin
                        sign_cov[2] <= average24(pair_left, pair_right);
                        sign_cov[6] <= average24(pair_left, pair_right);
                    end else begin
                        sign_cov[5] <= average24(pair_left, pair_right);
                        sign_cov[7] <= average24(pair_left, pair_right);
                    end
                    if (element_index == 4'd2) begin
                        element_index <= 4'd0;
                        if (NUM_BRANCHES == 1)
                            state <= ST_B_CALC;
                        else
                            state <= ST_SELF_M1;
                    end else begin
                        element_index <= element_index + 4'd1;
                    end
                end

                ST_SELF_M1: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_SELF_M1)) begin
                        scalar_temp <= pipe_rounded_product;
                        if (pipe_product_overflow) overflow_flag <= 1'b1;
                        element_index <= pipe_result_element_index;
                        state <= ST_SELF_M2;
                    end
                end

                ST_SELF_M2: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_SELF_M2)) begin
                        self_normalized[pipe_result_element_index] <= pipe_rounded_product;
                        if (pipe_product_overflow) overflow_flag <= 1'b1;
                        element_index <= pipe_result_element_index;
                        state <= ST_SELF_ASIN_REQ;
                    end
                end

                ST_SELF_ASIN_REQ: state <= ST_SELF_ASIN_WAIT;

                ST_SELF_ASIN_WAIT: begin
                    if (asin_valid) begin
                        scalar_temp <= asin_y;
                        if (asin_domain_error) numeric_error <= 1'b1;
                        state <= ST_SELF_REDUCE;
                    end
                end

                ST_SELF_REDUCE: begin
                    case (element_index)
                        4'd0: sign_cov[0] <= reduce_self_cov_l8(scalar_temp);
                        4'd1: sign_cov[4] <= reduce_self_cov_l8(scalar_temp);
                        default: sign_cov[8] <= reduce_self_cov_l8(scalar_temp);
                    endcase
                    if (element_index == 4'd2) begin
                        element_index <= 4'd0;
                        state <= ST_B_CALC;
                    end else begin
                        element_index <= element_index + 4'd1;
                        state <= ST_SELF_M1;
                    end
                end

                ST_EKF_S_COPY: begin
                    sign_cov[element_index] <= measurement_cov[element_index];
                    if (element_index == 4'd8) begin
                        b_diag[0] <= FX_ONE;
                        b_diag[1] <= FX_ONE;
                        b_diag[2] <= FX_ONE;
                        element_index <= 4'd0;
                        state <= ST_COF_P1;
                    end else begin
                        element_index <= element_index + 4'd1;
                    end
                end

                ST_B_CALC: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_B_CALC)) begin
                        b_diag[pipe_result_element_index] <= pipe_rounded_product;
                        if (pipe_product_overflow) overflow_flag <= 1'b1;
                        if (pipe_result_element_index == 4'd2) begin
                            element_index <= 4'd0;
                            state <= ST_COF_P1;
                        end else begin
                            element_index <= pipe_result_element_index + 4'd1;
                        end
                    end
                end

                ST_COF_P1: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_COF_P1)) begin
                        scalar_temp <= pipe_rounded_product;
                        if (pipe_product_overflow) overflow_flag <= 1'b1;
                        element_index <= pipe_result_element_index;
                        state <= ST_COF_P2;
                    end
                end

                ST_COF_P2: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_COF_P2)) begin
                        cofactor[pipe_result_element_index] <= sub_sat24(scalar_temp, pipe_rounded_product);
                        if (pipe_product_overflow || sub_overflow24(scalar_temp, pipe_rounded_product))
                            overflow_flag <= 1'b1;
                        if (pipe_result_element_index == 4'd8) begin
                            element_index <= 4'd0;
                            dot_index <= 2'd0;
                            mac_accumulator <= 50'sd0;
                            state <= ST_DET;
                        end else begin
                            element_index <= pipe_result_element_index + 4'd1;
                            state <= ST_COF_P1;
                        end
                    end
                end

                ST_DET: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_DET)) begin
                        if (pipe_result_dot_index == 2'd0) begin
                            mac_accumulator <= pipe_mac_sum;
                            dot_index <= 2'd1;
                        end else if (pipe_result_dot_index == 2'd1) begin
                            mac_accumulator <= pipe_mac_sum;
                            dot_index <= 2'd2;
                        end else begin
                            if (($signed(pipe_rounded_mac) < $signed(DET_FLOOR)) &&
                                ($signed(pipe_rounded_mac) > -$signed(DET_FLOOR))) begin
                                determinant <= pipe_rounded_mac[23] ? -DET_FLOOR : DET_FLOOR;
                                solver_error <= 1'b1;
                            end else begin
                                determinant <= pipe_rounded_mac;
                            end
                            if (pipe_mac_overflow) overflow_flag <= 1'b1;
                            element_index <= 4'd0;
                            dot_index <= 2'd0;
                            state <= ST_INV_DIV;
                        end
                    end
                end

                ST_INV_DIV: begin
                    state <= ST_INV_WAIT;
                end

                ST_INV_WAIT: begin
                    if (divider_valid) begin
                        sign_cov_inverse[element_index] <= divider_quotient;
                        if (divider_overflow) overflow_flag <= 1'b1;
                        if (divider_by_zero) begin
                            numeric_error <= 1'b1;
                            solver_error <= 1'b1;
                        end
                        if (element_index == 4'd8) begin
                            element_index <= 4'd0;
                            state <= ST_GAIN_INNER;
                        end else begin
                            element_index <= element_index + 4'd1;
                            state <= ST_INV_DIV;
                        end
                    end
                end

                ST_GAIN_INNER: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_GAIN_INNER)) begin
                        gain_inner[pipe_result_element_index] <= pipe_rounded_product;
                        if (pipe_product_overflow) overflow_flag <= 1'b1;
                        if (pipe_result_element_index == 4'd8) begin
                            row_index <= 2'd0;
                            col_index <= 2'd0;
                            dot_index <= 2'd0;
                            mac_accumulator <= 50'sd0;
                            state <= ST_GAIN;
                        end else begin
                            element_index <= pipe_result_element_index + 4'd1;
                        end
                    end
                end

                ST_X_MV: begin
                    if (pipe_result_valid && (pipe_result_operation == ST_X_MV)) begin
                        if (pipe_result_dot_index == 2'd0) begin
                            mac_accumulator <= pipe_mac_sum;
                            dot_index <= 2'd1;
                        end else if (pipe_result_dot_index == 2'd1) begin
                            mac_accumulator <= pipe_mac_sum;
                            dot_index <= 2'd2;
                        end else begin
                            state_correction[pipe_result_row_index] <= pipe_rounded_mac;
                            if (pipe_mac_overflow) overflow_flag <= 1'b1;
                            dot_index <= 2'd0;
                            mac_accumulator <= 50'sd0;
                            if (pipe_result_row_index == 2'd2) begin
                                row_index <= 2'd0;
                                element_index <= 4'd0;
                                state <= ST_X_ADD;
                            end else begin
                                row_index <= pipe_result_row_index + 2'd1;
                            end
                        end
                    end
                end

                ST_X_ADD: begin
                    state_post[element_index] <= add_sat24(state_predict[element_index], state_correction[element_index]);
                    if (add_overflow24(state_predict[element_index], state_correction[element_index])) overflow_flag <= 1'b1;
                    if (element_index == 4'd2) begin
                        row_index <= 2'd0;
                        col_index <= 2'd0;
                        dot_index <= 2'd0;
                        mac_accumulator <= 50'sd0;
                        state <= ST_COV_UP_INNER;
                    end else begin
                        element_index <= element_index + 4'd1;
                    end
                end

                ST_COV_SUB: begin
                    cov_post[element_index] <= sub_sat24(cov_predict[element_index], cov_correction[element_index]);
                    if (sub_overflow24(cov_predict[element_index], cov_correction[element_index])) overflow_flag <= 1'b1;
                    if (element_index == 4'd8) begin
                        element_index <= 4'd0;
                        if (EKF_MODE != 0)
                            state <= ST_POST_SYM;
                        else
                            state <= ST_RESULT;
                    end else begin
                        element_index <= element_index + 4'd1;
                    end
                end

                ST_POST_SYM: begin
                    if (element_index == 4'd0) begin
                        cov_post[1] <= average24(pair_left, pair_right);
                        cov_post[3] <= average24(pair_left, pair_right);
                    end else if (element_index == 4'd1) begin
                        cov_post[2] <= average24(pair_left, pair_right);
                        cov_post[6] <= average24(pair_left, pair_right);
                    end else begin
                        cov_post[5] <= average24(pair_left, pair_right);
                        cov_post[7] <= average24(pair_left, pair_right);
                    end
                    if (element_index == 4'd2) begin
                        element_index <= 4'd0;
                        state <= ST_RESULT;
                    end else begin
                        element_index <= element_index + 4'd1;
                    end
                end

                ST_RESULT: begin
                    if (result_ready)
                        state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                    numeric_error <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
