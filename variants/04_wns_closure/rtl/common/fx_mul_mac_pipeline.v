`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Register-separated shared arithmetic pipeline.
// Stage 1 captures decoded operands/control, stage 2 registers the full 48-bit
// product, stage 3 registers the rounded product and full 50-bit MAC sum, and
// the owning FSM commits the result to its architectural destination.
module fx_mul_mac_pipeline (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    request_valid,
    output wire                    request_ready,
    input  wire signed [23:0]      request_operand_a,
    input  wire signed [23:0]      request_operand_b,
    input  wire signed [49:0]      request_accumulator,
    input  wire [5:0]              request_operation,
    input  wire [3:0]              request_element_index,
    input  wire [1:0]              request_row_index,
    input  wire [1:0]              request_col_index,
    input  wire [1:0]              request_dot_index,

    output wire                    result_valid,
    input  wire                    result_ready,
    output wire signed [23:0]      result_rounded_product,
    output wire signed [49:0]      result_mac_sum,
    output wire signed [23:0]      result_rounded_mac,
    output wire                    result_product_overflow,
    output wire                    result_mac_overflow,
    output wire [5:0]              result_operation,
    output wire [3:0]              result_element_index,
    output wire [1:0]              result_row_index,
    output wire [1:0]              result_col_index,
    output wire [1:0]              result_dot_index,

    output wire                    stage1_valid,
    output wire                    stage2_valid,
    output wire                    stage3_valid
);
    reg stage1_valid_reg;
    reg stage2_valid_reg;
    reg stage3_valid_reg;

    reg signed [23:0] stage1_operand_a;
    reg signed [23:0] stage1_operand_b;
    reg signed [49:0] stage1_accumulator;
    reg [5:0] stage1_operation;
    reg [3:0] stage1_element_index;
    reg [1:0] stage1_row_index;
    reg [1:0] stage1_col_index;
    reg [1:0] stage1_dot_index;

    reg signed [47:0] stage2_product;
    reg signed [49:0] stage2_accumulator;
    reg [5:0] stage2_operation;
    reg [3:0] stage2_element_index;
    reg [1:0] stage2_row_index;
    reg [1:0] stage2_col_index;
    reg [1:0] stage2_dot_index;

    reg signed [23:0] stage3_rounded_product;
    reg signed [49:0] stage3_mac_sum;
    reg stage3_product_overflow;
    reg [5:0] stage3_operation;
    reg [3:0] stage3_element_index;
    reg [1:0] stage3_row_index;
    reg [1:0] stage3_col_index;
    reg [1:0] stage3_dot_index;

    wire signed [47:0] stage1_product;
    wire signed [49:0] stage2_product_extended;
    wire signed [49:0] stage2_mac_sum;

    `include "rtl/common/fx_q8_16_functions.vh"

    assign stage1_product = $signed(stage1_operand_a) * $signed(stage1_operand_b);
    assign stage2_product_extended = {{2{stage2_product[47]}}, stage2_product};
    assign stage2_mac_sum = stage2_accumulator + stage2_product_extended;

    assign request_ready = !stage1_valid_reg && !stage2_valid_reg && !stage3_valid_reg;
    assign result_valid = stage3_valid_reg;
    assign result_rounded_product = stage3_rounded_product;
    assign result_mac_sum = stage3_mac_sum;
    assign result_rounded_mac = round_sat50(stage3_mac_sum);
    assign result_product_overflow = stage3_product_overflow;
    assign result_mac_overflow = overflow50(stage3_mac_sum);
    assign result_operation = stage3_operation;
    assign result_element_index = stage3_element_index;
    assign result_row_index = stage3_row_index;
    assign result_col_index = stage3_col_index;
    assign result_dot_index = stage3_dot_index;
    assign stage1_valid = stage1_valid_reg;
    assign stage2_valid = stage2_valid_reg;
    assign stage3_valid = stage3_valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid_reg <= 1'b0;
            stage2_valid_reg <= 1'b0;
            stage3_valid_reg <= 1'b0;
            stage1_operand_a <= 24'sd0;
            stage1_operand_b <= 24'sd0;
            stage1_accumulator <= 50'sd0;
            stage1_operation <= 6'd0;
            stage1_element_index <= 4'd0;
            stage1_row_index <= 2'd0;
            stage1_col_index <= 2'd0;
            stage1_dot_index <= 2'd0;
            stage2_product <= 48'sd0;
            stage2_accumulator <= 50'sd0;
            stage2_operation <= 6'd0;
            stage2_element_index <= 4'd0;
            stage2_row_index <= 2'd0;
            stage2_col_index <= 2'd0;
            stage2_dot_index <= 2'd0;
            stage3_rounded_product <= 24'sd0;
            stage3_mac_sum <= 50'sd0;
            stage3_product_overflow <= 1'b0;
            stage3_operation <= 6'd0;
            stage3_element_index <= 4'd0;
            stage3_row_index <= 2'd0;
            stage3_col_index <= 2'd0;
            stage3_dot_index <= 2'd0;
        end else begin
            if (stage3_valid_reg && result_ready)
                stage3_valid_reg <= 1'b0;

            if (stage2_valid_reg && !stage3_valid_reg) begin
                stage3_valid_reg <= 1'b1;
                stage3_rounded_product <= round_sat48(stage2_product);
                stage3_mac_sum <= stage2_mac_sum;
                stage3_product_overflow <= overflow48(stage2_product);
                stage3_operation <= stage2_operation;
                stage3_element_index <= stage2_element_index;
                stage3_row_index <= stage2_row_index;
                stage3_col_index <= stage2_col_index;
                stage3_dot_index <= stage2_dot_index;
                stage2_valid_reg <= 1'b0;
            end

            if (stage1_valid_reg && !stage2_valid_reg) begin
                stage2_valid_reg <= 1'b1;
                stage2_product <= stage1_product;
                stage2_accumulator <= stage1_accumulator;
                stage2_operation <= stage1_operation;
                stage2_element_index <= stage1_element_index;
                stage2_row_index <= stage1_row_index;
                stage2_col_index <= stage1_col_index;
                stage2_dot_index <= stage1_dot_index;
                stage1_valid_reg <= 1'b0;
            end

            if (request_valid && request_ready) begin
                stage1_valid_reg <= 1'b1;
                stage1_operand_a <= request_operand_a;
                stage1_operand_b <= request_operand_b;
                stage1_accumulator <= request_accumulator;
                stage1_operation <= request_operation;
                stage1_element_index <= request_element_index;
                stage1_row_index <= request_row_index;
                stage1_col_index <= request_col_index;
                stage1_dot_index <= request_dot_index;
            end
        end
    end
endmodule

`default_nettype wire
