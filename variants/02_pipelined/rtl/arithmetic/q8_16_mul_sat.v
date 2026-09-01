`timescale 1ns/1ps
`default_nettype none

// Signed Q8.16 multiply. The full 48-bit product is rounded to nearest,
// with exact half cases away from zero, then saturated to 24 bits.
module q8_16_mul_sat (
    input  wire signed [23:0] a,
    input  wire signed [23:0] b,
    output reg  signed [23:0] y,
    output reg                overflow
);
    localparam signed [48:0] FX_MAX_EXT = 49'sd8388607;
    localparam signed [48:0] FX_MIN_EXT = -49'sd8388608;
    localparam signed [48:0] ROUND_HALF = 49'sd32768;

    wire signed [47:0] product;
    reg  signed [48:0] product_ext;
    reg  signed [48:0] rounded_ext;

    assign product = a * b;

    always @* begin
        product_ext = {product[47], product};
        if (product_ext < 0) begin
            rounded_ext = -(((-product_ext) + ROUND_HALF) >>> 16);
        end else begin
            rounded_ext = (product_ext + ROUND_HALF) >>> 16;
        end

        overflow = 1'b0;
        if (rounded_ext > FX_MAX_EXT) begin
            y        = 24'sh7fffff;
            overflow = 1'b1;
        end else if (rounded_ext < FX_MIN_EXT) begin
            y        = 24'sh800000;
            overflow = 1'b1;
        end else begin
            y = rounded_ext[23:0];
        end
    end
endmodule

`default_nettype wire
