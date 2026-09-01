`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

// Register-separated determinant finalization pipeline.
//
// A single full-precision determinant accumulator is captured, rounded and
// saturated at the existing Q8.16 boundary, checked against the strict
// determinant floor interval, and then copied to an aligned output register.
// The pipeline is intentionally single-issue because the shared estimator FSM
// produces one final determinant per matrix inverse operation.
module fx_determinant_finalize_pipeline (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    request_valid,
    output wire                    request_ready,
    input  wire signed [49:0]      request_accumulator,

    output wire                    result_valid,
    input  wire                    result_ready,
    output wire signed [23:0]      result_determinant,
    output wire                    result_solver_error,
    output wire                    result_overflow,

    output wire                    capture_stage_valid,
    output wire                    round_stage_valid,
    output wire                    floor_stage_valid
);
    localparam signed [23:0] DET_FLOOR = `FX_Q8_16_DET_FLOOR;

    reg capture_valid_reg;
    reg round_valid_reg;
    reg floor_valid_reg;
    reg result_valid_reg;

    reg signed [49:0] capture_accumulator_reg;

    reg signed [23:0] raw_determinant_reg;
    reg               raw_overflow_reg;

    reg signed [23:0] floor_determinant_reg;
    reg               floor_near_zero_reg;
    reg               floor_overflow_reg;

    reg signed [23:0] result_determinant_reg;
    reg               result_solver_error_reg;
    reg               result_overflow_reg;

    `include "rtl/common/fx_q8_16_functions.vh"

    assign request_ready = !capture_valid_reg && !round_valid_reg &&
                           !floor_valid_reg && !result_valid_reg;
    assign result_valid = result_valid_reg;
    assign result_determinant = result_determinant_reg;
    assign result_solver_error = result_solver_error_reg;
    assign result_overflow = result_overflow_reg;
    assign capture_stage_valid = capture_valid_reg;
    assign round_stage_valid = round_valid_reg;
    assign floor_stage_valid = floor_valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            capture_valid_reg <= 1'b0;
            round_valid_reg <= 1'b0;
            floor_valid_reg <= 1'b0;
            result_valid_reg <= 1'b0;
            capture_accumulator_reg <= 50'sd0;
            raw_determinant_reg <= 24'sd0;
            raw_overflow_reg <= 1'b0;
            floor_determinant_reg <= 24'sd0;
            floor_near_zero_reg <= 1'b0;
            floor_overflow_reg <= 1'b0;
            result_determinant_reg <= 24'sd0;
            result_solver_error_reg <= 1'b0;
            result_overflow_reg <= 1'b0;
        end else begin
            if (result_valid_reg && result_ready)
                result_valid_reg <= 1'b0;

            // Output alignment stage. Determinant, floor metadata, and
            // saturation metadata are committed together one cycle later.
            if (floor_valid_reg && !result_valid_reg) begin
                result_valid_reg <= 1'b1;
                result_determinant_reg <= floor_determinant_reg;
                result_solver_error_reg <= floor_near_zero_reg;
                result_overflow_reg <= floor_overflow_reg;
                floor_valid_reg <= 1'b0;
            end

            // Strict floor test: only -64 < determinant < 64 is clamped.
            // A rounded zero has a clear sign bit and therefore clamps to +64.
            if (round_valid_reg && !floor_valid_reg) begin
                floor_valid_reg <= 1'b1;
                if (($signed(raw_determinant_reg) < $signed(DET_FLOOR)) &&
                    ($signed(raw_determinant_reg) > -$signed(DET_FLOOR))) begin
                    floor_determinant_reg <= raw_determinant_reg[23] ?
                                             -DET_FLOOR : DET_FLOOR;
                    floor_near_zero_reg <= 1'b1;
                end else begin
                    floor_determinant_reg <= raw_determinant_reg;
                    floor_near_zero_reg <= 1'b0;
                end
                floor_overflow_reg <= raw_overflow_reg;
                round_valid_reg <= 1'b0;
            end

            // Existing Q8.16 round-to-nearest/ties-away and saturation point.
            if (capture_valid_reg && !round_valid_reg) begin
                round_valid_reg <= 1'b1;
                raw_determinant_reg <= round_sat50(capture_accumulator_reg);
                raw_overflow_reg <= overflow50(capture_accumulator_reg);
                capture_valid_reg <= 1'b0;
            end

            // Full signed 50-bit accumulator capture; no quantization occurs.
            if (request_valid && request_ready) begin
                capture_valid_reg <= 1'b1;
                capture_accumulator_reg <= request_accumulator;
            end
        end
    end
endmodule

`default_nettype wire
