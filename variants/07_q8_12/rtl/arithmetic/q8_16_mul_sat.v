`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Signed Q8.16 multiply. The full 2*W-bit product is rounded to nearest,
// with exact half cases away from zero, then saturated to W bits.
module q8_16_mul_sat (
    input  wire signed [`FX_Q8_16_WIDTH-1:0] a,
    input  wire signed [`FX_Q8_16_WIDTH-1:0] b,
    output reg  signed [`FX_Q8_16_WIDTH-1:0] y,
    output reg                overflow
);
    localparam signed [`FX_Q8_16_PRODUCT_WIDTH:0] FX_MAX_EXT = $signed(`FX_Q8_16_MAX);
    localparam signed [`FX_Q8_16_PRODUCT_WIDTH:0] FX_MIN_EXT = $signed(`FX_Q8_16_MIN);
    localparam signed [`FX_Q8_16_PRODUCT_WIDTH:0] ROUND_HALF = ({{`FX_Q8_16_PRODUCT_WIDTH{1'b0}}, 1'b1} <<< (`FX_Q8_16_FRAC-1));

    wire signed [`FX_Q8_16_PRODUCT_WIDTH-1:0] product;
    reg  signed [`FX_Q8_16_PRODUCT_WIDTH:0] product_ext;
    reg  signed [`FX_Q8_16_PRODUCT_WIDTH:0] rounded_ext;

    assign product = a * b;

    always @* begin
        product_ext = {product[`FX_Q8_16_PRODUCT_WIDTH-1], product};
        if (product_ext < 0) begin
            rounded_ext = -(((-product_ext) + ROUND_HALF) >>> `FX_Q8_16_FRAC);
        end else begin
            rounded_ext = (product_ext + ROUND_HALF) >>> `FX_Q8_16_FRAC;
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
