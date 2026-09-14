`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Saturating addition for signed W-bit Q8.F values.
module q8_16_add_sat (
    input  wire signed [`FX_Q8_16_WIDTH-1:0] a,
    input  wire signed [`FX_Q8_16_WIDTH-1:0] b,
    output reg  signed [`FX_Q8_16_WIDTH-1:0] y,
    output reg                overflow
);
    localparam signed [`FX_Q8_16_WIDTH:0] FX_MAX_EXT = $signed(`FX_Q8_16_MAX);
    localparam signed [`FX_Q8_16_WIDTH:0] FX_MIN_EXT = $signed(`FX_Q8_16_MIN);

    wire signed [`FX_Q8_16_WIDTH:0] sum_ext;

    assign sum_ext = {a[`FX_Q8_16_WIDTH-1], a} + {b[`FX_Q8_16_WIDTH-1], b};

    always @* begin
        overflow = 1'b0;
        if (sum_ext > FX_MAX_EXT) begin
            y        = `FX_Q8_16_MAX;
            overflow = 1'b1;
        end else if (sum_ext < FX_MIN_EXT) begin
            y        = `FX_Q8_16_MIN;
            overflow = 1'b1;
        end else begin
            y = sum_ext[`FX_Q8_16_WIDTH-1:0];
        end
    end
endmodule

`default_nettype wire
