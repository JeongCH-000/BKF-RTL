`timescale 1ns/1ps
`default_nettype none

module tb_fx_divider_q8_16;
    localparam integer RANDOM_VECTOR_COUNT = 2000;
    localparam integer RANDOM_SEED = 20260830;

    reg clk;
    reg rst_n;
    reg start;
    reg signed [23:0] numerator;
    reg signed [23:0] denominator;
    wire busy;
    wire valid;
    wire signed [23:0] quotient;
    wire divide_by_zero;
    wire overflow;

    integer cycle_count;
    integer accepted_count;
    integer completion_count;
    integer accepted_monitor_count;
    integer completion_monitor_count;
    integer directed_count;
    integer randomized_count;
    integer protocol_count;
    integer transaction_index;
    integer normal_latency;
    integer divide_by_zero_latency;
    integer normal_initiation_interval;
    integer last_nonzero_accept_cycle;
    reg previous_case_was_nonzero;
    integer random_seed;
    integer random_index;
    integer output_file;
    reg [2047:0] output_path;
    reg signed [23:0] random_numerator;
    reg signed [23:0] random_denominator;

    fx_divider_q8_16 dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .numerator(numerator), .denominator(denominator),
        .busy(busy), .valid(valid), .quotient(quotient),
        .divide_by_zero(divide_by_zero), .overflow(overflow)
    );

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            accepted_monitor_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (start && !busy)
                accepted_monitor_count <= accepted_monitor_count + 1;
        end
    end

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            completion_monitor_count = 0;
        end else if (valid) begin
            completion_monitor_count = completion_monitor_count + 1;
            if ((^quotient === 1'bx) ||
                (divide_by_zero !== 1'b0 && divide_by_zero !== 1'b1) ||
                (overflow !== 1'b0 && overflow !== 1'b1)) begin
                $display("FAIL: divider valid output contains X/Z");
                $fatal(1);
            end
        end
    end

    function signed [23:0] reference_divide;
        input signed [23:0] n;
        input signed [23:0] d;
        reg signed [24:0] n_ext;
        reg signed [24:0] d_ext;
        reg [24:0] n_mag;
        reg [24:0] d_mag;
        reg [40:0] scaled_numerator;
        reg [41:0] q_mag;
        reg negative;
        begin
            n_ext = {n[23], n};
            d_ext = {d[23], d};
            n_mag = n[23] ? -n_ext : n_ext;
            d_mag = d[23] ? -d_ext : d_ext;
            negative = n[23] ^ d[23];
            if (d_mag == 25'd0) begin
                reference_divide = n[23] ? 24'sh800000 : 24'sh7fffff;
            end else begin
                scaled_numerator = {n_mag, 16'd0};
                q_mag = (scaled_numerator + (d_mag >> 1)) / d_mag;
                if (!negative && (q_mag > 42'd8388607))
                    reference_divide = 24'sh7fffff;
                else if (negative && (q_mag > 42'd8388608))
                    reference_divide = 24'sh800000;
                else if (negative && (q_mag == 42'd8388608))
                    reference_divide = 24'sh800000;
                else if (negative)
                    reference_divide = -$signed(q_mag[23:0]);
                else
                    reference_divide = q_mag[23:0];
            end
        end
    endfunction

    function reference_overflow;
        input signed [23:0] n;
        input signed [23:0] d;
        reg signed [24:0] n_ext;
        reg signed [24:0] d_ext;
        reg [24:0] n_mag;
        reg [24:0] d_mag;
        reg [40:0] scaled_numerator;
        reg [41:0] q_mag;
        reg negative;
        begin
            n_ext = {n[23], n};
            d_ext = {d[23], d};
            n_mag = n[23] ? -n_ext : n_ext;
            d_mag = d[23] ? -d_ext : d_ext;
            negative = n[23] ^ d[23];
            if (d_mag == 25'd0) begin
                reference_overflow = 1'b1;
            end else begin
                scaled_numerator = {n_mag, 16'd0};
                q_mag = (scaled_numerator + (d_mag >> 1)) / d_mag;
                reference_overflow = (!negative && (q_mag > 42'd8388607)) ||
                                     (negative && (q_mag > 42'd8388608));
            end
        end
    endfunction

    task fail;
        input [8*96-1:0] message;
        begin
            $display("FAIL: %0s", message);
            $fatal(1);
        end
    endtask

    task record_response;
        input signed [23:0] n;
        input signed [23:0] d;
        input integer case_type;
        input integer accept_cycle;
        input integer observed_latency;
        begin
            if (output_file != 0) begin
                $fdisplay(output_file, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                          transaction_index, case_type, $signed(n), $signed(d),
                          $signed(quotient), divide_by_zero, overflow,
                          accept_cycle, observed_latency);
            end
            transaction_index = transaction_index + 1;
        end
    endtask

    task check_latency;
        input signed [23:0] d;
        input integer observed_latency;
        begin
            if (d == 24'sd0) begin
                if (divide_by_zero_latency < 0)
                    divide_by_zero_latency = observed_latency;
                else if (observed_latency != divide_by_zero_latency)
                    fail("divide-by-zero latency varied");
            end else begin
                if (normal_latency < 0)
                    normal_latency = observed_latency;
                else if (observed_latency != normal_latency)
                    fail("nonzero divider latency varied");
            end
        end
    endtask

    task run_case;
        input signed [23:0] n;
        input signed [23:0] d;
        input integer case_type;
        reg signed [23:0] expected_quotient;
        reg expected_overflow;
        integer accept_cycle;
        integer observed_latency;
        integer observed_interval;
        begin
            while (busy) @(negedge clk);
            numerator = n;
            denominator = d;
            expected_quotient = reference_divide(n, d);
            expected_overflow = reference_overflow(n, d);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            accept_cycle = cycle_count;
            accepted_count = accepted_count + 1;
            if (d != 24'sd0) begin
                if (previous_case_was_nonzero) begin
                    observed_interval = accept_cycle - last_nonzero_accept_cycle;
                    if (normal_initiation_interval < 0)
                        normal_initiation_interval = observed_interval;
                    else if (observed_interval != normal_initiation_interval)
                        fail("nonzero divider initiation interval varied");
                end
                last_nonzero_accept_cycle = accept_cycle;
                previous_case_was_nonzero = 1'b1;
            end else begin
                previous_case_was_nonzero = 1'b0;
            end
            while (!valid) @(negedge clk);
            observed_latency = cycle_count - accept_cycle;
            if (($signed(quotient) !== $signed(expected_quotient)) ||
                (divide_by_zero !== (d == 24'sd0)) ||
                (overflow !== expected_overflow)) begin
                $display("FAIL divider transaction=%0d n=%0d d=%0d exp=%0d got=%0d div0_exp=%0d div0=%0d ovf_exp=%0d ovf=%0d",
                         transaction_index, n, d, expected_quotient, quotient,
                         (d == 24'sd0), divide_by_zero,
                         expected_overflow, overflow);
                $fatal(1);
            end
            check_latency(d, observed_latency);
            completion_count = completion_count + 1;
            record_response(n, d, case_type, accept_cycle, observed_latency);
            if (case_type == 0)
                directed_count = directed_count + 1;
            else if (case_type == 1)
                randomized_count = randomized_count + 1;
            else
                protocol_count = protocol_count + 1;
        end
    endtask

    task test_reset_flush;
        integer wait_cycle;
        begin
            numerator = 24'sd196608;
            denominator = 24'sd131072;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            repeat (5) @(negedge clk);
            if (!busy)
                fail("divider left busy before reset test");
            rst_n = 1'b0;
            #1;
            if (busy || valid)
                fail("reset did not flush divider pipeline");
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            for (wait_cycle = 0; wait_cycle < 50; wait_cycle = wait_cycle + 1) begin
                @(negedge clk);
                if (valid)
                    fail("aborted transaction completed after reset");
            end
        end
    endtask

    task test_start_while_busy;
        reg signed [23:0] first_expected;
        integer accept_cycle;
        integer observed_latency;
        begin
            while (busy) @(negedge clk);
            numerator = 24'sd196608;
            denominator = 24'sd131072;
            first_expected = reference_divide(numerator, denominator);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            accept_cycle = cycle_count;
            accepted_count = accepted_count + 1;
            last_nonzero_accept_cycle = accept_cycle;
            previous_case_was_nonzero = 1'b1;
            repeat (5) @(negedge clk);
            if (!busy)
                fail("busy was not held during active transaction");
            numerator = -24'sd65536;
            denominator = 24'sd65536;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            while (!valid) @(negedge clk);
            observed_latency = cycle_count - accept_cycle;
            if (($signed(quotient) !== $signed(first_expected)) ||
                divide_by_zero || overflow)
                fail("start while busy replaced the active transaction");
            check_latency(24'sd131072, observed_latency);
            completion_count = completion_count + 1;
            record_response(24'sd196608, 24'sd131072, 2,
                            accept_cycle, observed_latency);
            protocol_count = protocol_count + 1;
            run_case(-24'sd65536, 24'sd65536, 2);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        numerator = 24'sd0;
        denominator = 24'sd0;
        cycle_count = 0;
        accepted_count = 0;
        completion_count = 0;
        accepted_monitor_count = 0;
        completion_monitor_count = 0;
        directed_count = 0;
        randomized_count = 0;
        protocol_count = 0;
        transaction_index = 0;
        normal_latency = -1;
        divide_by_zero_latency = -1;
        normal_initiation_interval = -1;
        last_nonzero_accept_cycle = 0;
        previous_case_was_nonzero = 1'b0;
        random_seed = RANDOM_SEED;
        output_file = 0;
        output_path = "results/divider_transactions.csv";
        if ($value$plusargs("OUTPUT=%s", output_path)) begin
            output_file = $fopen(output_path, "w");
        end else begin
            output_file = $fopen("results/divider_transactions.csv", "w");
        end
        if (output_file == 0)
            fail("could not open divider transaction output");
        $fdisplay(output_file,
                  "transaction,case_type,numerator,denominator,quotient,divide_by_zero,overflow,accept_cycle,latency_cycles");

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        test_reset_flush();

        // Directed numeric, rounding, saturation, sign, and two's-complement cases.
        run_case(24'sd0, 24'sd65536, 0);
        run_case(24'sd196608, 24'sd131072, 0);
        run_case(24'sd65536, -24'sd65536, 0);
        run_case(-24'sd65536, 24'sd65536, 0);
        run_case(-24'sd65536, -24'sd65536, 0);
        run_case(24'sd65536, 24'sd65536, 0);
        run_case(24'sh7fffff, 24'sd65536, 0);
        run_case(24'sh800000, 24'sd65536, 0);
        run_case(24'sd1, 24'sh7fffff, 0);
        run_case(24'sd131072, 24'sd65536, 0);
        run_case(24'sd65536, 24'sd196608, 0);
        run_case(24'sd1, 24'sd131072, 0);
        run_case(-24'sd1, 24'sd131072, 0);
        run_case(24'sd6554, 24'sd19661, 0);
        run_case(24'sh7ffffe, 24'sd65536, 0);
        run_case(-24'sd8388607, 24'sd65536, 0);
        run_case(24'sh7fffff, 24'sd1, 0);
        run_case(-24'sd8388607, 24'sd1, 0);
        run_case(24'sh800000, -24'sd65536, 0);
        run_case(24'sd1234, 24'sd0, 0);
        run_case(-24'sd1234, 24'sd0, 0);
        run_case(24'sd0, 24'sd0, 0);
        run_case(24'sh800000, 24'sh800000, 0);
        run_case(24'sh7fffff, 24'sh800000, 0);
        run_case(24'sh800000, 24'sh7fffff, 0);
        run_case(24'sd1, -24'sd131072, 0);
        run_case(-24'sd1, -24'sd131072, 0);

        test_start_while_busy();

        for (random_index = 0;
             random_index < RANDOM_VECTOR_COUNT;
             random_index = random_index + 1) begin
            random_numerator = $random(random_seed);
            random_denominator = $random(random_seed);
            run_case(random_numerator, random_denominator, 1);
        end

        @(negedge clk);
        #1;
        if (valid)
            fail("valid was not a completion pulse");
        if (busy)
            fail("busy remained asserted after final completion");
        if ((accepted_count != completion_count) ||
            (accepted_count != accepted_monitor_count) ||
            (completion_count != completion_monitor_count)) begin
            $display("FAIL: transaction accounting accepted=%0d completed=%0d accepted_monitor=%0d completion_monitor=%0d",
                     accepted_count, completion_count,
                     accepted_monitor_count, completion_monitor_count);
            $fatal(1);
        end
        if (randomized_count != RANDOM_VECTOR_COUNT)
            fail("randomized vector count mismatch");

        $fclose(output_file);
        $display("PASS: divider directed=%0d randomized=%0d protocol=%0d mismatch=0 seed=%0d latency_nonzero=%0d latency_div0=%0d initiation_interval_nonzero=%0d accepted=%0d completed=%0d",
                 directed_count, randomized_count, protocol_count, RANDOM_SEED,
                 normal_latency, divide_by_zero_latency, normal_initiation_interval,
                 accepted_count, completion_count);
        $finish;
    end

    initial begin
        #5000000;
        $display("FAIL: divider timeout transaction=%0d busy=%0d valid=%0d",
                 transaction_index, busy, valid);
        $fatal(1);
    end
endmodule

`default_nettype wire
