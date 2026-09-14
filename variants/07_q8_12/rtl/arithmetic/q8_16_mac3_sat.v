`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Three-term Q8.16 dot product. Products remain at full 2*W-bit precision;
// a signed (2*W+2)-bit accumulator is rounded once and then saturated.
module q8_16_mac3_sat (
    input  wire signed [`FX_Q8_16_WIDTH-1:0] a0,
    input  wire signed [`FX_Q8_16_WIDTH-1:0] b0,
    input  wire signed [`FX_Q8_16_WIDTH-1:0] a1,
    input  wire signed [`FX_Q8_16_WIDTH-1:0] b1,
    input  wire signed [`FX_Q8_16_WIDTH-1:0] a2,
    input  wire signed [`FX_Q8_16_WIDTH-1:0] b2,
    output reg  signed [`FX_Q8_16_WIDTH-1:0] y,
    output reg                overflow
);
    localparam signed [`FX_Q8_16_MAC_WIDTH:0] FX_MAX_EXT = $signed(`FX_Q8_16_MAX);
    localparam signed [`FX_Q8_16_MAC_WIDTH:0] FX_MIN_EXT = $signed(`FX_Q8_16_MIN);
    localparam signed [`FX_Q8_16_MAC_WIDTH:0] ROUND_HALF = ({{`FX_Q8_16_MAC_WIDTH{1'b0}}, 1'b1} <<< (`FX_Q8_16_FRAC-1));

    wire signed [`FX_Q8_16_PRODUCT_WIDTH-1:0] product0;
    wire signed [`FX_Q8_16_PRODUCT_WIDTH-1:0] product1;
    wire signed [`FX_Q8_16_PRODUCT_WIDTH-1:0] product2;
    wire signed [`FX_Q8_16_MAC_WIDTH-1:0] accumulator;
    reg  signed [`FX_Q8_16_MAC_WIDTH:0] accumulator_ext;
    reg  signed [`FX_Q8_16_MAC_WIDTH:0] rounded_ext;

    assign product0 = a0 * b0;
    assign product1 = a1 * b1;
    assign product2 = a2 * b2;
    assign accumulator = {{2{product0[`FX_Q8_16_PRODUCT_WIDTH-1]}}, product0}
                       + {{2{product1[`FX_Q8_16_PRODUCT_WIDTH-1]}}, product1}
                       + {{2{product2[`FX_Q8_16_PRODUCT_WIDTH-1]}}, product2};

    always @* begin
        accumulator_ext = {accumulator[`FX_Q8_16_MAC_WIDTH-1], accumulator};
        if (accumulator_ext < 0) begin
            rounded_ext = -(((-accumulator_ext) + ROUND_HALF) >>> `FX_Q8_16_FRAC);
        end else begin
            rounded_ext = (accumulator_ext + ROUND_HALF) >>> `FX_Q8_16_FRAC;
        end

        overflow = 1'b0;
        if (rounded_ext > FX_MAX_EXT) begin
            y        = `FX_Q8_16_MAX;
            overflow = 1'b1;
        end else if (rounded_ext < FX_MIN_EXT) begin
            y        = `FX_Q8_16_MIN;
            overflow = 1'b1;
        end else begin
            y = rounded_ext[`FX_Q8_16_WIDTH-1:0];
        end
    end
endmodule

`default_nettype wire
