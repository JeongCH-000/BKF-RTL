`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

module tb_fx_determinant_finalize_pipeline;
    reg clk;
    reg rst_n;
    reg request_valid;
    wire request_ready;
    reg signed [49:0] request_accumulator;
    wire result_valid;
    reg result_ready;
    wire signed [23:0] result_determinant;
    wire result_solver_error;
    wire result_overflow;
    wire capture_stage_valid;
    wire round_stage_valid;
    wire floor_stage_valid;

    integer cycle_count;
    integer accepted_count;
    integer completed_count;
    integer accepted_monitor_count;
    integer completed_monitor_count;
    integer directed_count;
    integer protocol_count;
    integer measured_latency;

    reg signed [23:0] held_determinant;
    reg held_solver_error;
    reg held_overflow;

    `include "rtl/common/fx_q8_16_functions.vh"

    fx_determinant_finalize_pipeline dut (
        .clk(clk),
        .rst_n(rst_n),
        .request_valid(request_valid),
        .request_ready(request_ready),
        .request_accumulator(request_accumulator),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_determinant(result_determinant),
        .result_solver_error(result_solver_error),
        .result_overflow(result_overflow),
        .capture_stage_valid(capture_stage_valid),
        .round_stage_valid(round_stage_valid),
        .floor_stage_valid(floor_stage_valid)
    );

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            accepted_monitor_count <= 0;
            completed_monitor_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (request_valid && request_ready)
                accepted_monitor_count <= accepted_monitor_count + 1;
            if (result_valid && result_ready)
                completed_monitor_count <= completed_monitor_count + 1;

            if ((capture_stage_valid && round_stage_valid) ||
                (capture_stage_valid && floor_stage_valid) ||
                (capture_stage_valid && result_valid) ||
                (round_stage_valid && floor_stage_valid) ||
                (round_stage_valid && result_valid) ||
                (floor_stage_valid && result_valid)) begin
                $display("FAIL: determinant pipeline stages overlap");
                $fatal(1);
            end

            if (result_valid &&
                ((^result_determinant === 1'bx) ||
                 ((result_solver_error !== 1'b0) &&
                  (result_solver_error !== 1'b1)) ||
                 ((result_overflow !== 1'b0) &&
                  (result_overflow !== 1'b1)))) begin
                $display("FAIL: determinant valid output contains X/Z");
                $fatal(1);
            end
        end
    end

    task fail;
        input [8*80-1:0] message;
        begin
            $display("FAIL: %0s cycle=%0d", message, cycle_count);
            $fatal(1);
        end
    endtask

    // Build the exact pre-finalizer accumulator from an explicit Q8.16
    // matrix.  Cofactor products are rounded separately before subtraction,
    // while the three determinant products remain full precision until the
    // finalizer.  This mirrors the unchanged shared-engine arithmetic order.
    task run_matrix_case;
        input signed [23:0] matrix0;
        input signed [23:0] matrix1;
        input signed [23:0] matrix2;
        input signed [23:0] matrix3;
        input signed [23:0] matrix4;
        input signed [23:0] matrix5;
        input signed [23:0] matrix6;
        input signed [23:0] matrix7;
        input signed [23:0] matrix8;
        input signed [23:0] expected_determinant;
        input expected_solver_error;
        input expected_overflow;
        input [8*40-1:0] case_name;
        reg signed [47:0] minor_product_a;
        reg signed [47:0] minor_product_b;
        reg signed [23:0] cofactor0;
        reg signed [23:0] cofactor1;
        reg signed [23:0] cofactor2;
        reg signed [47:0] determinant_product0;
        reg signed [47:0] determinant_product1;
        reg signed [47:0] determinant_product2;
        reg signed [49:0] determinant_accumulator;
        begin
            minor_product_a = matrix4 * matrix8;
            minor_product_b = matrix5 * matrix7;
            cofactor0 = sub_sat24(round_sat48(minor_product_a),
                                  round_sat48(minor_product_b));
            minor_product_a = matrix5 * matrix6;
            minor_product_b = matrix3 * matrix8;
            cofactor1 = sub_sat24(round_sat48(minor_product_a),
                                  round_sat48(minor_product_b));
            minor_product_a = matrix3 * matrix7;
            minor_product_b = matrix4 * matrix6;
            cofactor2 = sub_sat24(round_sat48(minor_product_a),
                                  round_sat48(minor_product_b));

            determinant_product0 = matrix0 * cofactor0;
            determinant_product1 = matrix1 * cofactor1;
            determinant_product2 = matrix2 * cofactor2;
            determinant_accumulator = {{2{determinant_product0[47]}},
                                       determinant_product0};
            determinant_accumulator = determinant_accumulator +
                                      {{2{determinant_product1[47]}},
                                       determinant_product1};
            determinant_accumulator = determinant_accumulator +
                                      {{2{determinant_product2[47]}},
                                       determinant_product2};
            run_case(determinant_accumulator, expected_determinant,
                     expected_solver_error, expected_overflow, 0, case_name);
        end
    endtask

    task check_result;
        input signed [23:0] expected_determinant;
        input expected_solver_error;
        input expected_overflow;
        input [8*40-1:0] case_name;
        begin
            if (($signed(result_determinant) !== $signed(expected_determinant)) ||
                (result_solver_error !== expected_solver_error) ||
                (result_overflow !== expected_overflow)) begin
                $display("FAIL: case=%0s determinant expected=%0d actual=%0d solver expected=%b actual=%b overflow expected=%b actual=%b",
                         case_name, expected_determinant, result_determinant,
                         expected_solver_error, result_solver_error,
                         expected_overflow, result_overflow);
                $fatal(1);
            end
        end
    endtask

    task run_case;
        input signed [49:0] accumulator;
        input signed [23:0] expected_determinant;
        input expected_solver_error;
        input expected_overflow;
        input integer case_type;
        input [8*40-1:0] case_name;
        integer accept_cycle;
        integer observed_latency;
        begin
            while (!request_ready) @(negedge clk);
            request_accumulator = accumulator;
            request_valid = 1'b1;
            @(negedge clk);
            request_valid = 1'b0;
            accept_cycle = cycle_count;
            accepted_count = accepted_count + 1;

            if (!capture_stage_valid || round_stage_valid ||
                floor_stage_valid || result_valid)
                fail("capture stage sequence");
            @(negedge clk);
            if (capture_stage_valid || !round_stage_valid ||
                floor_stage_valid || result_valid)
                fail("round stage sequence");
            @(negedge clk);
            if (capture_stage_valid || round_stage_valid ||
                !floor_stage_valid || result_valid)
                fail("floor stage sequence");
            @(negedge clk);
            if (capture_stage_valid || round_stage_valid ||
                floor_stage_valid || !result_valid)
                fail("aligned output stage sequence");

            observed_latency = cycle_count - accept_cycle;
            if (measured_latency < 0)
                measured_latency = observed_latency;
            else if (observed_latency != measured_latency)
                fail("determinant latency varied");
            if (observed_latency != 3)
                fail("determinant latency is not three cycles");

            check_result(expected_determinant, expected_solver_error,
                         expected_overflow, case_name);
            completed_count = completed_count + 1;
            if (case_type == 0)
                directed_count = directed_count + 1;
            else
                protocol_count = protocol_count + 1;
        end
    endtask

    task test_reset_flush;
        integer wait_cycle;
        begin
            while (!request_ready) @(negedge clk);
            request_accumulator = 50'sd6553600;
            request_valid = 1'b1;
            @(negedge clk);
            request_valid = 1'b0;
            if (!capture_stage_valid)
                fail("reset test request was not captured");
            @(negedge clk);
            if (!round_stage_valid)
                fail("reset test did not reach round stage");

            rst_n = 1'b0;
            #1;
            if (capture_stage_valid || round_stage_valid || floor_stage_valid ||
                result_valid)
                fail("reset did not flush determinant pipeline");
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            for (wait_cycle = 0; wait_cycle < 8; wait_cycle = wait_cycle + 1) begin
                @(negedge clk);
                if (result_valid)
                    fail("aborted determinant transaction completed after reset");
            end
        end
    endtask

    task test_backpressure_and_rejected_request;
        integer hold_cycle;
        integer accepted_before_rejected_request;
        begin
            while (!request_ready) @(negedge clk);
            result_ready = 1'b0;
            request_accumulator = 50'sd6553600;
            request_valid = 1'b1;
            @(negedge clk);
            request_valid = 1'b0;
            accepted_count = accepted_count + 1;
            if (!capture_stage_valid)
                fail("protocol request was not captured");

            @(negedge clk);
            if (!round_stage_valid)
                fail("protocol request missed round stage");

            accepted_before_rejected_request = accepted_monitor_count;
            request_accumulator = -50'sd13107200;
            request_valid = 1'b1;
            @(negedge clk);
            request_valid = 1'b0;
            if (accepted_monitor_count != accepted_before_rejected_request)
                fail("request was accepted while determinant pipeline busy");
            if (!floor_stage_valid)
                fail("protocol request missed floor stage");

            @(negedge clk);
            if (!result_valid || request_ready)
                fail("protocol output/backpressure state");
            check_result(24'sd100, 1'b0, 1'b0, "backpressure");
            held_determinant = result_determinant;
            held_solver_error = result_solver_error;
            held_overflow = result_overflow;

            for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
                @(negedge clk);
                if (!result_valid || request_ready ||
                    ($signed(result_determinant) !== $signed(held_determinant)) ||
                    (result_solver_error !== held_solver_error) ||
                    (result_overflow !== held_overflow))
                    fail("result payload changed under backpressure");
            end

            result_ready = 1'b1;
            @(negedge clk);
            if (result_valid || !request_ready)
                fail("result handshake did not release determinant pipeline");
            completed_count = completed_count + 1;
            protocol_count = protocol_count + 1;

            // The pulse while request_ready was low was discarded. Submit the
            // same payload normally and require exactly one corresponding result.
            run_case(-50'sd13107200, -24'sd200, 1'b0, 1'b0, 1,
                     "accepted_after_busy");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        request_valid = 1'b0;
        request_accumulator = 50'sd0;
        result_ready = 1'b1;
        cycle_count = 0;
        accepted_count = 0;
        completed_count = 0;
        accepted_monitor_count = 0;
        completed_monitor_count = 0;
        directed_count = 0;
        protocol_count = 0;
        measured_latency = -1;
        held_determinant = 24'sd0;
        held_solver_error = 1'b0;
        held_overflow = 1'b0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        test_reset_flush();

        accepted_count = 0;
        completed_count = 0;
        directed_count = 0;
        protocol_count = 0;
        measured_latency = -1;

        // Explicit matrix cases exercise the unchanged cofactor/determinant
        // association before the new finalizer boundary.
        run_matrix_case(
            `FX_Q8_16_ONE, 24'sd0, 24'sd0,
            24'sd0, `FX_Q8_16_ONE, 24'sd0,
            24'sd0, 24'sd0, `FX_Q8_16_ONE,
            `FX_Q8_16_ONE, 1'b0, 1'b0, "identity_matrix");
        run_matrix_case(
            24'sd0, 24'sd0, 24'sd0,
            24'sd0, 24'sd0, 24'sd0,
            24'sd0, 24'sd0, 24'sd0,
            `FX_Q8_16_DET_FLOOR, 1'b1, 1'b0, "zero_matrix");
        run_matrix_case(
            24'sd131072, 24'sd0, 24'sd0,
            24'sd0, 24'sd196608, 24'sd0,
            24'sd0, 24'sd0, -24'sd65536,
            -24'sd393216, 1'b0, 1'b0, "signed_diagonal_matrix");

        // Near-zero, strict floor, and rounding boundaries.
        run_case(-50'sd16384, 24'sd64, 1'b1, 1'b0, 0, "negative_rounds_to_zero");
        run_case(50'sd4128768, 24'sd64, 1'b1, 1'b0, 0, "positive_near_floor");
        run_case(-50'sd4128768, -24'sd64, 1'b1, 1'b0, 0, "negative_near_floor");
        run_case(50'sd4194304, 24'sd64, 1'b0, 1'b0, 0, "positive_exact_floor");
        run_case(-50'sd4194304, -24'sd64, 1'b0, 1'b0, 0, "negative_exact_floor");
        run_case(50'sd6586367, 24'sd100, 1'b0, 1'b0, 0, "positive_below_half");
        run_case(50'sd6586368, 24'sd101, 1'b0, 1'b0, 0, "positive_exact_half");
        run_case(-50'sd6586367, -24'sd100, 1'b0, 1'b0, 0, "negative_below_half");
        run_case(-50'sd6586368, -24'sd101, 1'b0, 1'b0, 0, "negative_exact_half");

        // Exact Q8.16 endpoints, saturation boundaries, and full 50-bit limits.
        run_case(50'sd549755748352, 24'sh7fffff, 1'b0, 1'b0, 0, "maximum_q8_16");
        run_case(-50'sd549755813888, 24'sh800000, 1'b0, 1'b0, 0, "minimum_q8_16");
        run_case(50'sd549755781120, 24'sh7fffff, 1'b0, 1'b1, 0, "positive_saturation");
        run_case(-50'sd549755846656, 24'sh800000, 1'b0, 1'b1, 0, "negative_saturation");
        run_case(50'sh1ffffffffffff, 24'sh7fffff, 1'b0, 1'b1, 0, "maximum_accumulator");
        run_case(50'sh2000000000000, 24'sh800000, 1'b0, 1'b1, 0, "minimum_accumulator");

        test_backpressure_and_rejected_request();

        // Allow the final ready/valid handshake to update monitor accounting.
        repeat (2) @(negedge clk);
        if (result_valid)
            fail("result_valid did not clear after final transaction");
        if ((accepted_count != completed_count) ||
            (accepted_count != accepted_monitor_count) ||
            (completed_count != completed_monitor_count)) begin
            $display("FAIL: determinant accounting accepted=%0d completed=%0d accepted_monitor=%0d completed_monitor=%0d",
                     accepted_count, completed_count,
                     accepted_monitor_count, completed_monitor_count);
            $fatal(1);
        end
        if ((directed_count != 18) || (protocol_count != 2))
            fail("determinant directed/protocol count mismatch");

        $display("PASS: determinant finalize directed=%0d protocol=%0d mismatch=0 latency=%0d accepted=%0d completed=%0d",
                 directed_count, protocol_count, measured_latency,
                 accepted_count, completed_count);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: determinant finalize timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
