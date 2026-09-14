`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

module q8_16_rsqrt_lut (
    input  wire                     clk,
    input  wire                     en,
    input  wire signed [`FX_Q8_16_WIDTH-1:0]       x,
    output reg  signed [`FX_Q8_16_WIDTH-1:0]       y,
    output reg                      valid,
    output reg                      domain_error
);

    localparam signed [`FX_Q8_16_WIDTH-1:0] DIAG_FLOOR_Q = `FX_Q8_16_DIAG_FLOOR;
    localparam signed [`FX_Q8_16_WIDTH-1:0] LUT_LIMIT_Q  = (`FX_Q8_16_ONE <<< 2);

    reg signed [`FX_Q8_16_WIDTH-1:0] lut [0:4095];
    reg        [11:0] lut_address;

    initial begin
        $readmemh("rtl/nonlinear/rsqrt_q16.hex", lut);
    end

    // Preserve the 2^-10 grid: floor at 2^-10, shift F-10, clamp at 4095.
    always @* begin
        if (x < DIAG_FLOOR_Q) begin
            lut_address = 12'd1;
        end else if (x >= LUT_LIMIT_Q) begin
            lut_address = 12'd4095;
        end else begin
            lut_address = x[`FX_Q8_16_RSQRT_ADDR_SHIFT +: 12];
        end
    end

    always @(posedge clk) begin
        valid <= en;
        if (en) begin
            y <= lut[lut_address];
            domain_error <= (x < DIAG_FLOOR_Q);
        end else begin
            domain_error <= 1'b0;
        end
    end

endmodule

`default_nettype wire
