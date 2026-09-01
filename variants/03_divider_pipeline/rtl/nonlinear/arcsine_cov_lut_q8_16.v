`timescale 1ns/1ps
`default_nettype none

// Element-wise (2/pi)*asin(x), not a raw asin lookup.
module arcsine_cov_lut_q8_16 (
    input  wire                     clk,
    input  wire                     en,
    input  wire signed [23:0]       x,
    output reg  signed [23:0]       y,
    output reg                      valid,
    output reg                      domain_error
);
    localparam signed [23:0] NEG_ONE_Q = -24'sd65536;
    localparam signed [23:0] POS_ONE_Q =  24'sd65536;
    reg signed [23:0] lut [0:4096];
    reg [12:0] lut_address;
    wire signed [24:0] x_extended;
    wire signed [24:0] biased_x;

    assign x_extended = {x[23], x};
    assign biased_x = x_extended + 25'sd65536;

    initial begin
        $readmemh("rtl/nonlinear/arcsine_cov_q16.hex", lut);
    end

    // Clamp [-1,1], bias by one, and address a 2^-11 grid.
    always @* begin
        if (x <= NEG_ONE_Q)
            lut_address = 13'd0;
        else if (x >= POS_ONE_Q)
            lut_address = 13'd4096;
        else
            lut_address = biased_x[17:5];
    end

    always @(posedge clk) begin
        valid <= en;
        if (en) begin
            y <= lut[lut_address];
            domain_error <= (x < NEG_ONE_Q) || (x > POS_ONE_Q);
        end else begin
            domain_error <= 1'b0;
        end
    end
endmodule

`default_nettype wire
