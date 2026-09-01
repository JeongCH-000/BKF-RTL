`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Iterative unsigned-magnitude divider with signed Q8.16 I/O.
// Computes round-to-nearest/ties-away((numerator << 16) / denominator)
// in 42 clocks and saturates to the signed 24-bit range.
module fx_divider_q8_16 (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire signed [23:0]      numerator,
    input  wire signed [23:0]      denominator,
    output reg                     busy,
    output reg                     valid,
    output reg signed [23:0]       quotient,
    output reg                     divide_by_zero,
    output reg                     overflow
);
    reg [40:0] dividend_reg;
    reg [24:0] divisor_reg;
    reg [41:0] remainder_reg;
    reg [40:0] quotient_reg;
    reg [5:0] bit_index;
    reg negative_result;

    reg signed [24:0] numerator_ext;
    reg signed [24:0] denominator_ext;
    reg [24:0] numerator_mag;
    reg [24:0] denominator_mag;
    reg [41:0] shifted_remainder;
    reg [40:0] quotient_next;
    reg [41:0] remainder_next;
    reg [41:0] rounded_magnitude;

    always @* begin
        numerator_ext = {numerator[23], numerator};
        denominator_ext = {denominator[23], denominator};
        numerator_mag = numerator[23] ? -numerator_ext : numerator_ext;
        denominator_mag = denominator[23] ? -denominator_ext : denominator_ext;

        shifted_remainder = {remainder_reg[40:0], dividend_reg[bit_index]};
        quotient_next = quotient_reg;
        remainder_next = shifted_remainder;
        if (shifted_remainder >= {17'd0, divisor_reg}) begin
            remainder_next = shifted_remainder - {17'd0, divisor_reg};
            quotient_next[bit_index] = 1'b1;
        end
        rounded_magnitude = {1'b0, quotient_next};
        if ((remainder_next << 1) >= {17'd0, divisor_reg})
            rounded_magnitude = rounded_magnitude + 42'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            valid <= 1'b0;
            quotient <= 24'sd0;
            divide_by_zero <= 1'b0;
            overflow <= 1'b0;
            dividend_reg <= 41'd0;
            divisor_reg <= 25'd0;
            remainder_reg <= 42'd0;
            quotient_reg <= 41'd0;
            bit_index <= 6'd0;
            negative_result <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (start && !busy) begin
                divide_by_zero <= (denominator_mag == 0);
                overflow <= 1'b0;
                negative_result <= numerator[23] ^ denominator[23];
                if (denominator_mag == 0) begin
                    quotient <= numerator[23] ? `FX_Q8_16_MIN : `FX_Q8_16_MAX;
                    busy <= 1'b0;
                    valid <= 1'b1;
                    overflow <= 1'b1;
                end else begin
                    dividend_reg <= {numerator_mag, 16'd0};
                    divisor_reg <= denominator_mag;
                    remainder_reg <= 42'd0;
                    quotient_reg <= 41'd0;
                    bit_index <= 6'd40;
                    busy <= 1'b1;
                end
            end else if (busy) begin
                remainder_reg <= remainder_next;
                quotient_reg <= quotient_next;
                if (bit_index == 0) begin
                    busy <= 1'b0;
                    valid <= 1'b1;
                    if ((!negative_result && (rounded_magnitude > 42'd8388607)) ||
                        (negative_result && (rounded_magnitude > 42'd8388608))) begin
                        quotient <= negative_result ? `FX_Q8_16_MIN : `FX_Q8_16_MAX;
                        overflow <= 1'b1;
                    end else if (negative_result && (rounded_magnitude == 42'd8388608)) begin
                        quotient <= `FX_Q8_16_MIN;
                    end else if (negative_result) begin
                        quotient <= -$signed(rounded_magnitude[23:0]);
                    end else begin
                        quotient <= rounded_magnitude[23:0];
                    end
                end else begin
                    bit_index <= bit_index - 6'd1;
                end
            end
        end
    end
endmodule

`default_nettype wire
