`timescale 1ns/1ps
`default_nettype none

module q8_16_rsqrt_lut (
    input  wire                     clk,
    input  wire                     en,
    input  wire signed [23:0]       x,
    output reg  signed [23:0]       y,
    output reg                      valid,
    output reg                      domain_error
);

    localparam signed [23:0] DIAG_FLOOR_Q = 24'sd64;
    localparam signed [23:0] LUT_LIMIT_Q  = 24'sd262144;

    reg signed [23:0] lut [0:4095];
    reg        [11:0] lut_address;

    initial begin
        $readmemh("rtl/nonlinear/rsqrt_q16.hex", lut);
    end

    /* Python reference: floor to 64, shift right by 6, clamp to 4095. */
    always @* begin
        if (x < DIAG_FLOOR_Q) begin
            lut_address = 12'd1;
        end else if (x >= LUT_LIMIT_Q) begin
            lut_address = 12'd4095;
        end else begin
            lut_address = x[17:6];
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
