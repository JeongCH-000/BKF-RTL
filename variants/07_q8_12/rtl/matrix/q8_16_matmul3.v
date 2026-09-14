`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Combinational 3x3 matrix reference unit used for independent datapath tests.
// The production core schedules the same nine dot products over one shared multiplier.
module q8_16_matmul3 (
    input  wire [9*`FX_Q8_16_WIDTH-1:0] a_flat,
    input  wire [9*`FX_Q8_16_WIDTH-1:0] b_flat,
    output wire [9*`FX_Q8_16_WIDTH-1:0] y_flat,
    output wire         overflow
);
    wire signed [`FX_Q8_16_WIDTH-1:0] a [0:8];
    wire signed [`FX_Q8_16_WIDTH-1:0] b [0:8];
    wire signed [`FX_Q8_16_WIDTH-1:0] y [0:8];
    wire [8:0] element_overflow;

    genvar unpack_index;
    generate
        for (unpack_index = 0; unpack_index < 9; unpack_index = unpack_index + 1) begin : UNPACK
            assign a[unpack_index] = $signed(a_flat[(unpack_index*`FX_Q8_16_WIDTH) +: `FX_Q8_16_WIDTH]);
            assign b[unpack_index] = $signed(b_flat[(unpack_index*`FX_Q8_16_WIDTH) +: `FX_Q8_16_WIDTH]);
            assign y_flat[(unpack_index*`FX_Q8_16_WIDTH) +: `FX_Q8_16_WIDTH] = y[unpack_index];
        end
    endgenerate

    genvar row;
    genvar column;
    generate
        for (row = 0; row < 3; row = row + 1) begin : ROW
            for (column = 0; column < 3; column = column + 1) begin : COLUMN
                q8_16_mac3_sat u_dot (
                    .a0(a[(row*3)+0]), .b0(b[(0*3)+column]),
                    .a1(a[(row*3)+1]), .b1(b[(1*3)+column]),
                    .a2(a[(row*3)+2]), .b2(b[(2*3)+column]),
                    .y(y[(row*3)+column]),
                    .overflow(element_overflow[(row*3)+column])
                );
            end
        end
    endgenerate

    assign overflow = |element_overflow;
endmodule

`default_nettype wire

