`timescale 1ns/1ps
`default_nettype none

// Three-term Q8.16 dot product. Products remain at full 48-bit precision;
// a signed 50-bit accumulator is rounded once and then saturated.
module q8_16_mac3_sat (
    input  wire signed [23:0] a0,
    input  wire signed [23:0] b0,
    input  wire signed [23:0] a1,
    input  wire signed [23:0] b1,
    input  wire signed [23:0] a2,
    input  wire signed [23:0] b2,
    output reg  signed [23:0] y,
    output reg                overflow
);
    localparam signed [50:0] FX_MAX_EXT = 51'sd8388607;
    localparam signed [50:0] FX_MIN_EXT = -51'sd8388608;
    localparam signed [50:0] ROUND_HALF = 51'sd32768;

    wire signed [47:0] product0;
    wire signed [47:0] product1;
    wire signed [47:0] product2;
    wire signed [49:0] accumulator;
    reg  signed [50:0] accumulator_ext;
    reg  signed [50:0] rounded_ext;

    assign product0 = a0 * b0;
    assign product1 = a1 * b1;
    assign product2 = a2 * b2;
    assign accumulator = {{2{product0[47]}}, product0}
                       + {{2{product1[47]}}, product1}
                       + {{2{product2[47]}}, product2};

    always @* begin
        accumulator_ext = {accumulator[49], accumulator};
        if (accumulator_ext < 0) begin
            rounded_ext = -(((-accumulator_ext) + ROUND_HALF) >>> 16);
        end else begin
            rounded_ext = (accumulator_ext + ROUND_HALF) >>> 16;
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
