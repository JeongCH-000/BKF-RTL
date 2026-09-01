`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Sequential 3x3 adjugate/determinant inverse. Cofactors and determinant use
// the same Q8.16 rounding boundaries as the Python model; one iterative
// divider is reused for all nine adjugate elements.
module mat3_inverse_q8_16 (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire [215:0]            matrix_flat,
    output wire                    busy,
    output reg                     valid,
    output wire [215:0]            inverse_flat,
    output reg signed [23:0]       determinant,
    output reg                     solver_error,
    output reg                     overflow
);
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_DIV_START = 2'd1;
    localparam [1:0] ST_DIV_WAIT = 2'd2;

    wire signed [23:0] matrix [0:8];
    wire signed [23:0] product_a [0:8];
    wire signed [23:0] product_b [0:8];
    wire signed [23:0] cofactor_wire [0:8];
    wire [8:0] product_a_overflow;
    wire [8:0] product_b_overflow;
    wire [8:0] subtract_overflow;
    wire signed [23:0] determinant_wire;
    wire determinant_overflow;

    reg [1:0] state;
    reg [3:0] element_index;
    reg signed [23:0] cofactor_hold [0:8];
    reg signed [23:0] inverse [0:8];
    reg signed [23:0] divider_numerator;
    wire divider_start;
    wire divider_busy;
    wire divider_valid;
    wire signed [23:0] divider_quotient;
    wire divider_by_zero;
    wire divider_overflow;
    integer reset_index;
    integer load_index;

    assign busy = (state != ST_IDLE);
    assign divider_start = (state == ST_DIV_START);

    genvar io_index;
    generate
        for (io_index = 0; io_index < 9; io_index = io_index + 1) begin : IO
            assign matrix[io_index] = $signed(matrix_flat[(io_index*24) +: 24]);
            assign inverse_flat[(io_index*24) +: 24] = inverse[io_index];
        end
    endgenerate

    q8_16_mul_sat p00a(.a(matrix[4]),.b(matrix[8]),.y(product_a[0]),.overflow(product_a_overflow[0]));
    q8_16_mul_sat p00b(.a(matrix[5]),.b(matrix[7]),.y(product_b[0]),.overflow(product_b_overflow[0]));
    q8_16_mul_sat p01a(.a(matrix[5]),.b(matrix[6]),.y(product_a[1]),.overflow(product_a_overflow[1]));
    q8_16_mul_sat p01b(.a(matrix[3]),.b(matrix[8]),.y(product_b[1]),.overflow(product_b_overflow[1]));
    q8_16_mul_sat p02a(.a(matrix[3]),.b(matrix[7]),.y(product_a[2]),.overflow(product_a_overflow[2]));
    q8_16_mul_sat p02b(.a(matrix[4]),.b(matrix[6]),.y(product_b[2]),.overflow(product_b_overflow[2]));
    q8_16_mul_sat p10a(.a(matrix[2]),.b(matrix[7]),.y(product_a[3]),.overflow(product_a_overflow[3]));
    q8_16_mul_sat p10b(.a(matrix[1]),.b(matrix[8]),.y(product_b[3]),.overflow(product_b_overflow[3]));
    q8_16_mul_sat p11a(.a(matrix[0]),.b(matrix[8]),.y(product_a[4]),.overflow(product_a_overflow[4]));
    q8_16_mul_sat p11b(.a(matrix[2]),.b(matrix[6]),.y(product_b[4]),.overflow(product_b_overflow[4]));
    q8_16_mul_sat p12a(.a(matrix[1]),.b(matrix[6]),.y(product_a[5]),.overflow(product_a_overflow[5]));
    q8_16_mul_sat p12b(.a(matrix[0]),.b(matrix[7]),.y(product_b[5]),.overflow(product_b_overflow[5]));
    q8_16_mul_sat p20a(.a(matrix[1]),.b(matrix[5]),.y(product_a[6]),.overflow(product_a_overflow[6]));
    q8_16_mul_sat p20b(.a(matrix[2]),.b(matrix[4]),.y(product_b[6]),.overflow(product_b_overflow[6]));
    q8_16_mul_sat p21a(.a(matrix[2]),.b(matrix[3]),.y(product_a[7]),.overflow(product_a_overflow[7]));
    q8_16_mul_sat p21b(.a(matrix[0]),.b(matrix[5]),.y(product_b[7]),.overflow(product_b_overflow[7]));
    q8_16_mul_sat p22a(.a(matrix[0]),.b(matrix[4]),.y(product_a[8]),.overflow(product_a_overflow[8]));
    q8_16_mul_sat p22b(.a(matrix[1]),.b(matrix[3]),.y(product_b[8]),.overflow(product_b_overflow[8]));

    genvar cofactor_index;
    generate
        for (cofactor_index = 0; cofactor_index < 9; cofactor_index = cofactor_index + 1) begin : COFACTOR
            q8_16_sub_sat u_sub (
                .a(product_a[cofactor_index]), .b(product_b[cofactor_index]),
                .y(cofactor_wire[cofactor_index]), .overflow(subtract_overflow[cofactor_index])
            );
        end
    endgenerate

    q8_16_mac3_sat u_determinant (
        .a0(matrix[0]), .b0(cofactor_wire[0]),
        .a1(matrix[1]), .b1(cofactor_wire[1]),
        .a2(matrix[2]), .b2(cofactor_wire[2]),
        .y(determinant_wire), .overflow(determinant_overflow)
    );

    always @* begin
        case (element_index)
            4'd0: divider_numerator = cofactor_hold[0];
            4'd1: divider_numerator = cofactor_hold[3];
            4'd2: divider_numerator = cofactor_hold[6];
            4'd3: divider_numerator = cofactor_hold[1];
            4'd4: divider_numerator = cofactor_hold[4];
            4'd5: divider_numerator = cofactor_hold[7];
            4'd6: divider_numerator = cofactor_hold[2];
            4'd7: divider_numerator = cofactor_hold[5];
            default: divider_numerator = cofactor_hold[8];
        endcase
    end

    fx_divider_q8_16 u_divider (
        .clk(clk), .rst_n(rst_n), .start(divider_start),
        .numerator(divider_numerator), .denominator(determinant),
        .busy(divider_busy), .valid(divider_valid), .quotient(divider_quotient),
        .divide_by_zero(divider_by_zero), .overflow(divider_overflow)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            valid <= 1'b0;
            element_index <= 4'd0;
            determinant <= 24'sd0;
            solver_error <= 1'b0;
            overflow <= 1'b0;
            for (reset_index = 0; reset_index < 9; reset_index = reset_index + 1) begin
                cofactor_hold[reset_index] <= 24'sd0;
                inverse[reset_index] <= 24'sd0;
            end
        end else begin
            valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        for (load_index = 0; load_index < 9; load_index = load_index + 1)
                            cofactor_hold[load_index] <= cofactor_wire[load_index];
                        if (($signed(determinant_wire) < $signed(`FX_Q8_16_DET_FLOOR)) &&
                            ($signed(determinant_wire) > -$signed(`FX_Q8_16_DET_FLOOR))) begin
                            determinant <= determinant_wire[23] ? -`FX_Q8_16_DET_FLOOR : `FX_Q8_16_DET_FLOOR;
                            solver_error <= 1'b1;
                        end else begin
                            determinant <= determinant_wire;
                            solver_error <= 1'b0;
                        end
                        overflow <= (|product_a_overflow) || (|product_b_overflow) ||
                                    (|subtract_overflow) || determinant_overflow;
                        element_index <= 4'd0;
                        state <= ST_DIV_START;
                    end
                end
                ST_DIV_START: state <= ST_DIV_WAIT;
                ST_DIV_WAIT: begin
                    if (divider_valid) begin
                        inverse[element_index] <= divider_quotient;
                        if (divider_overflow || divider_by_zero) overflow <= 1'b1;
                        if (element_index == 4'd8) begin
                            element_index <= 4'd0;
                            valid <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            element_index <= element_index + 4'd1;
                            state <= ST_DIV_START;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
