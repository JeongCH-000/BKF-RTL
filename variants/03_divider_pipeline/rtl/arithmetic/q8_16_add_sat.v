`timescale 1ns/1ps
`default_nettype none

// Saturating addition for signed 24-bit Q8.16 values.
module q8_16_add_sat (
    input  wire signed [23:0] a,
    input  wire signed [23:0] b,
    output reg  signed [23:0] y,
    output reg                overflow
);
    localparam signed [24:0] FX_MAX_EXT = 25'sd8388607;
    localparam signed [24:0] FX_MIN_EXT = -25'sd8388608;

    wire signed [24:0] sum_ext;

    assign sum_ext = {a[23], a} + {b[23], b};

    always @* begin
        overflow = 1'b0;
        if (sum_ext > FX_MAX_EXT) begin
            y        = 24'sh7fffff;
            overflow = 1'b1;
        end else if (sum_ext < FX_MIN_EXT) begin
            y        = 24'sh800000;
            overflow = 1'b1;
        end else begin
            y = sum_ext[23:0];
        end
    end
endmodule

`default_nettype wire
