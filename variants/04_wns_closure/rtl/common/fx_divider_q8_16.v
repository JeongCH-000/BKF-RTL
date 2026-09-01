`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Register-separated iterative unsigned-magnitude divider with signed Q8.16
// I/O. Computes round-to-nearest/ties-away((numerator << 16) / denominator)
// in 44 clocks and saturates to the signed 24-bit range.
module fx_divider_q8_16 (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire signed [23:0]      numerator,
    input  wire signed [23:0]      denominator,
    output reg                     busy,
    output reg                     valid,
    output reg signed [23:0]       quotient,
    output reg                     divide_by_zero,
    output reg                     overflow
);
    localparam integer DATA_WIDTH = `FX_Q8_16_WIDTH;
    localparam integer FRACTION_WIDTH = `FX_Q8_16_FRAC;
    localparam integer MAGNITUDE_WIDTH = DATA_WIDTH + 1;
    localparam integer DIVIDEND_WIDTH = MAGNITUDE_WIDTH + FRACTION_WIDTH;
    localparam integer REMAINDER_WIDTH = DIVIDEND_WIDTH + 1;
    localparam integer ITERATION_COUNT = DIVIDEND_WIDTH;

    function integer width_for_count;
        input integer value;
        integer working_value;
        begin
            working_value = value - 1;
            width_for_count = 0;
            while (working_value > 0) begin
                width_for_count = width_for_count + 1;
                working_value = working_value >> 1;
            end
        end
    endfunction

    localparam integer COUNT_WIDTH = width_for_count(ITERATION_COUNT + 1);
    localparam [COUNT_WIDTH-1:0] ITERATION_COUNT_VALUE = ITERATION_COUNT;
    localparam [COUNT_WIDTH-1:0] ONE_ITERATION = {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
    localparam [REMAINDER_WIDTH-1:0] POSITIVE_OUTPUT_LIMIT = {
        {(REMAINDER_WIDTH-DATA_WIDTH){1'b0}},
        1'b0, {(DATA_WIDTH-1){1'b1}}
    };
    localparam [REMAINDER_WIDTH-1:0] NEGATIVE_OUTPUT_LIMIT = {
        {(REMAINDER_WIDTH-DATA_WIDTH){1'b0}},
        1'b1, {(DATA_WIDTH-1){1'b0}}
    };

    // Input capture registers. The calculation stages never reference the raw
    // numerator or denominator after a nonzero transaction is accepted.
    reg [DIVIDEND_WIDTH-1:0] dividend_input_reg;
    reg [MAGNITUDE_WIDTH-1:0] divisor_input_reg;
    reg negative_input_reg;
    reg divide_by_zero_input_reg;
    reg overflow_input_reg;
    reg input_valid_reg;

    // DIV_STAGE_A holds the full-precision restoring state. Each visit to
    // DIV_STAGE_B returns the next partial state through this register bank.
    reg [REMAINDER_WIDTH-1:0] partial_remainder_stage_a;
    reg [DIVIDEND_WIDTH-1:0] partial_quotient_stage_a;
    reg [DIVIDEND_WIDTH-1:0] remaining_dividend_stage_a;
    reg [MAGNITUDE_WIDTH-1:0] divisor_stage_a;
    reg negative_stage_a;
    reg divide_by_zero_stage_a;
    reg overflow_stage_a;
    reg [COUNT_WIDTH-1:0] iterations_remaining_stage_a;
    reg stage_a_valid;

    // DIV_STAGE_B captures the last restoring result before rounding, sign
    // restoration, saturation, and output commit.
    reg [REMAINDER_WIDTH-1:0] remainder_stage_b;
    reg [DIVIDEND_WIDTH-1:0] quotient_stage_b;
    reg [MAGNITUDE_WIDTH-1:0] divisor_stage_b;
    reg negative_stage_b;
    reg divide_by_zero_stage_b;
    reg overflow_stage_b;
    reg stage_b_valid;

    reg signed [MAGNITUDE_WIDTH-1:0] numerator_ext;
    reg signed [MAGNITUDE_WIDTH-1:0] denominator_ext;
    reg [MAGNITUDE_WIDTH-1:0] numerator_mag;
    reg [MAGNITUDE_WIDTH-1:0] denominator_mag;
    reg [REMAINDER_WIDTH-1:0] divisor_extended_stage_a;
    reg [REMAINDER_WIDTH-1:0] remainder_after_iteration;
    reg [DIVIDEND_WIDTH-1:0] quotient_after_iteration;
    reg [REMAINDER_WIDTH-1:0] next_partial_remainder_stage_a;
    reg [REMAINDER_WIDTH-1:0] divisor_extended_stage_b;
    reg [REMAINDER_WIDTH-1:0] rounded_magnitude_stage_b;

    always @* begin
        numerator_ext = {numerator[DATA_WIDTH-1], numerator};
        denominator_ext = {denominator[DATA_WIDTH-1], denominator};
        numerator_mag = numerator[DATA_WIDTH-1] ? -numerator_ext : numerator_ext;
        denominator_mag = denominator[DATA_WIDTH-1] ? -denominator_ext : denominator_ext;

        divisor_extended_stage_a =
            {{(REMAINDER_WIDTH-MAGNITUDE_WIDTH){1'b0}}, divisor_stage_a};
        remainder_after_iteration = partial_remainder_stage_a;
        quotient_after_iteration =
            {partial_quotient_stage_a[DIVIDEND_WIDTH-2:0], 1'b0};
        if (partial_remainder_stage_a >= divisor_extended_stage_a) begin
            remainder_after_iteration =
                partial_remainder_stage_a - divisor_extended_stage_a;
            quotient_after_iteration[0] = 1'b1;
        end
        next_partial_remainder_stage_a = {
            remainder_after_iteration[REMAINDER_WIDTH-2:0],
            remaining_dividend_stage_a[DIVIDEND_WIDTH-1]
        };

        divisor_extended_stage_b =
            {{(REMAINDER_WIDTH-MAGNITUDE_WIDTH){1'b0}}, divisor_stage_b};
        rounded_magnitude_stage_b = {1'b0, quotient_stage_b};
        if ((remainder_stage_b << 1) >= divisor_extended_stage_b)
            rounded_magnitude_stage_b =
                rounded_magnitude_stage_b + {{(REMAINDER_WIDTH-1){1'b0}}, 1'b1};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            valid <= 1'b0;
            quotient <= 24'sd0;
            divide_by_zero <= 1'b0;
            overflow <= 1'b0;
            dividend_input_reg <= {DIVIDEND_WIDTH{1'b0}};
            divisor_input_reg <= {MAGNITUDE_WIDTH{1'b0}};
            negative_input_reg <= 1'b0;
            divide_by_zero_input_reg <= 1'b0;
            overflow_input_reg <= 1'b0;
            input_valid_reg <= 1'b0;
            partial_remainder_stage_a <= {REMAINDER_WIDTH{1'b0}};
            partial_quotient_stage_a <= {DIVIDEND_WIDTH{1'b0}};
            remaining_dividend_stage_a <= {DIVIDEND_WIDTH{1'b0}};
            divisor_stage_a <= {MAGNITUDE_WIDTH{1'b0}};
            negative_stage_a <= 1'b0;
            divide_by_zero_stage_a <= 1'b0;
            overflow_stage_a <= 1'b0;
            iterations_remaining_stage_a <= {COUNT_WIDTH{1'b0}};
            stage_a_valid <= 1'b0;
            remainder_stage_b <= {REMAINDER_WIDTH{1'b0}};
            quotient_stage_b <= {DIVIDEND_WIDTH{1'b0}};
            divisor_stage_b <= {MAGNITUDE_WIDTH{1'b0}};
            negative_stage_b <= 1'b0;
            divide_by_zero_stage_b <= 1'b0;
            overflow_stage_b <= 1'b0;
            stage_b_valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (start && !busy) begin
                divide_by_zero <= (denominator_mag == {MAGNITUDE_WIDTH{1'b0}});
                overflow <= 1'b0;
                input_valid_reg <= 1'b0;
                stage_a_valid <= 1'b0;
                stage_b_valid <= 1'b0;
                if (denominator_mag == {MAGNITUDE_WIDTH{1'b0}}) begin
                    quotient <= numerator[DATA_WIDTH-1] ?
                                `FX_Q8_16_MIN : `FX_Q8_16_MAX;
                    busy <= 1'b0;
                    valid <= 1'b1;
                    overflow <= 1'b1;
                end else begin
                    dividend_input_reg <= {
                        numerator_mag, {FRACTION_WIDTH{1'b0}}
                    };
                    divisor_input_reg <= denominator_mag;
                    negative_input_reg <=
                        numerator[DATA_WIDTH-1] ^ denominator[DATA_WIDTH-1];
                    divide_by_zero_input_reg <= 1'b0;
                    overflow_input_reg <= 1'b0;
                    input_valid_reg <= 1'b1;
                    busy <= 1'b1;
                end
            end else if (busy) begin
                if (stage_b_valid) begin
                    stage_b_valid <= 1'b0;
                    busy <= 1'b0;
                    valid <= 1'b1;
                    divide_by_zero <= divide_by_zero_stage_b;
                    if ((!negative_stage_b &&
                         (rounded_magnitude_stage_b > POSITIVE_OUTPUT_LIMIT)) ||
                        (negative_stage_b &&
                         (rounded_magnitude_stage_b > NEGATIVE_OUTPUT_LIMIT))) begin
                        quotient <= negative_stage_b ?
                                    `FX_Q8_16_MIN : `FX_Q8_16_MAX;
                        overflow <= 1'b1;
                    end else if (negative_stage_b &&
                                 (rounded_magnitude_stage_b == NEGATIVE_OUTPUT_LIMIT)) begin
                        quotient <= `FX_Q8_16_MIN;
                        overflow <= overflow_stage_b;
                    end else if (negative_stage_b) begin
                        quotient <= -$signed(rounded_magnitude_stage_b[DATA_WIDTH-1:0]);
                        overflow <= overflow_stage_b;
                    end else begin
                        quotient <= rounded_magnitude_stage_b[DATA_WIDTH-1:0];
                        overflow <= overflow_stage_b;
                    end
                end else if (input_valid_reg) begin
                    input_valid_reg <= 1'b0;
                    partial_remainder_stage_a <= {
                        {(REMAINDER_WIDTH-1){1'b0}},
                        dividend_input_reg[DIVIDEND_WIDTH-1]
                    };
                    partial_quotient_stage_a <= {DIVIDEND_WIDTH{1'b0}};
                    remaining_dividend_stage_a <= {
                        dividend_input_reg[DIVIDEND_WIDTH-2:0], 1'b0
                    };
                    divisor_stage_a <= divisor_input_reg;
                    negative_stage_a <= negative_input_reg;
                    divide_by_zero_stage_a <= divide_by_zero_input_reg;
                    overflow_stage_a <= overflow_input_reg;
                    iterations_remaining_stage_a <= ITERATION_COUNT_VALUE;
                    stage_a_valid <= 1'b1;
                end else if (stage_a_valid) begin
                    if (iterations_remaining_stage_a == ONE_ITERATION) begin
                        remainder_stage_b <= remainder_after_iteration;
                        quotient_stage_b <= quotient_after_iteration;
                        divisor_stage_b <= divisor_stage_a;
                        negative_stage_b <= negative_stage_a;
                        divide_by_zero_stage_b <= divide_by_zero_stage_a;
                        overflow_stage_b <= overflow_stage_a;
                        stage_a_valid <= 1'b0;
                        stage_b_valid <= 1'b1;
                    end else begin
                        partial_remainder_stage_a <= next_partial_remainder_stage_a;
                        partial_quotient_stage_a <= quotient_after_iteration;
                        remaining_dividend_stage_a <= {
                            remaining_dividend_stage_a[DIVIDEND_WIDTH-2:0], 1'b0
                        };
                        iterations_remaining_stage_a <=
                            iterations_remaining_stage_a - ONE_ITERATION;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
