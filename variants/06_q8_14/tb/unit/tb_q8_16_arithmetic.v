`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

module tb_q8_16_arithmetic;
    `include "tb/unit/fx_format_tb.vh"
    reg  signed [W-1:0] add_a;
    reg  signed [W-1:0] add_b;
    wire signed [W-1:0] add_y;
    wire               add_overflow;

    reg  signed [W-1:0] sub_a;
    reg  signed [W-1:0] sub_b;
    wire signed [W-1:0] sub_y;
    wire               sub_overflow;

    reg  signed [W-1:0] mul_a;
    reg  signed [W-1:0] mul_b;
    wire signed [W-1:0] mul_y;
    wire               mul_overflow;

    reg  signed [W-1:0] mac_a0;
    reg  signed [W-1:0] mac_b0;
    reg  signed [W-1:0] mac_a1;
    reg  signed [W-1:0] mac_b1;
    reg  signed [W-1:0] mac_a2;
    reg  signed [W-1:0] mac_b2;
    wire signed [W-1:0] mac_y;
    wire               mac_overflow;

    integer failures;
    integer checks;
    integer index;
    integer random_seed;
    reg signed [W-1:0] random_a;
    reg signed [W-1:0] random_b;
    reg signed [W-1:0] random_c;
    reg signed [W-1:0] random_d;
    reg signed [W-1:0] random_e;
    reg signed [W-1:0] random_f;

    q8_16_add_sat dut_add (
        .a(add_a),
        .b(add_b),
        .y(add_y),
        .overflow(add_overflow)
    );

    q8_16_sub_sat dut_sub (
        .a(sub_a),
        .b(sub_b),
        .y(sub_y),
        .overflow(sub_overflow)
    );

    q8_16_mul_sat dut_mul (
        .a(mul_a),
        .b(mul_b),
        .y(mul_y),
        .overflow(mul_overflow)
    );

    q8_16_mac3_sat dut_mac (
        .a0(mac_a0),
        .b0(mac_b0),
        .a1(mac_a1),
        .b1(mac_b1),
        .a2(mac_a2),
        .b2(mac_b2),
        .y(mac_y),
        .overflow(mac_overflow)
    );

    task check_add;
        input signed [W-1:0] task_a;
        input signed [W-1:0] task_b;
        reg signed [63:0] left_ext;
        reg signed [63:0] right_ext;
        reg signed [63:0] result_ext;
        reg signed [W-1:0] expected_y;
        reg expected_overflow;
        begin
            add_a = task_a;
            add_b = task_b;
            #1;
            left_ext = task_a;
            right_ext = task_b;
            result_ext = left_ext + right_ext;
            expected_overflow = 1'b0;
            if (result_ext > TB_MAX) begin
                expected_y = TB_MAX_WORD;
                expected_overflow = 1'b1;
            end else if (result_ext < -(-TB_MIN)) begin
                expected_y = TB_MIN_WORD;
                expected_overflow = 1'b1;
            end else begin
                expected_y = result_ext[W-1:0];
            end
            checks = checks + 1;
            if ((add_y !== expected_y) || (add_overflow !== expected_overflow)) begin
                failures = failures + 1;
                $display("ADD mismatch a=%0d b=%0d got=%0d ov=%b expected=%0d ov=%b",
                         task_a, task_b, add_y, add_overflow, expected_y, expected_overflow);
            end
        end
    endtask

    task check_sub;
        input signed [W-1:0] task_a;
        input signed [W-1:0] task_b;
        reg signed [63:0] left_ext;
        reg signed [63:0] right_ext;
        reg signed [63:0] result_ext;
        reg signed [W-1:0] expected_y;
        reg expected_overflow;
        begin
            sub_a = task_a;
            sub_b = task_b;
            #1;
            left_ext = task_a;
            right_ext = task_b;
            result_ext = left_ext - right_ext;
            expected_overflow = 1'b0;
            if (result_ext > TB_MAX) begin
                expected_y = TB_MAX_WORD;
                expected_overflow = 1'b1;
            end else if (result_ext < -(-TB_MIN)) begin
                expected_y = TB_MIN_WORD;
                expected_overflow = 1'b1;
            end else begin
                expected_y = result_ext[W-1:0];
            end
            checks = checks + 1;
            if ((sub_y !== expected_y) || (sub_overflow !== expected_overflow)) begin
                failures = failures + 1;
                $display("SUB mismatch a=%0d b=%0d got=%0d ov=%b expected=%0d ov=%b",
                         task_a, task_b, sub_y, sub_overflow, expected_y, expected_overflow);
            end
        end
    endtask

    task check_mul;
        input signed [W-1:0] task_a;
        input signed [W-1:0] task_b;
        reg signed [63:0] left_ext;
        reg signed [63:0] right_ext;
        reg signed [63:0] product_ext;
        reg signed [63:0] rounded_ext;
        reg signed [W-1:0] expected_y;
        reg expected_overflow;
        begin
            mul_a = task_a;
            mul_b = task_b;
            #1;
            left_ext = task_a;
            right_ext = task_b;
            product_ext = left_ext * right_ext;
            if (product_ext < 0) begin
                rounded_ext = -(((-product_ext) + TB_HALF) >>> F);
            end else begin
                rounded_ext = (product_ext + TB_HALF) >>> F;
            end
            expected_overflow = 1'b0;
            if (rounded_ext > TB_MAX) begin
                expected_y = TB_MAX_WORD;
                expected_overflow = 1'b1;
            end else if (rounded_ext < -(-TB_MIN)) begin
                expected_y = TB_MIN_WORD;
                expected_overflow = 1'b1;
            end else begin
                expected_y = rounded_ext[W-1:0];
            end
            checks = checks + 1;
            if ((mul_y !== expected_y) || (mul_overflow !== expected_overflow)) begin
                failures = failures + 1;
                $display("MUL mismatch a=%0d b=%0d got=%0d ov=%b expected=%0d ov=%b",
                         task_a, task_b, mul_y, mul_overflow, expected_y, expected_overflow);
            end
        end
    endtask

    task check_mac;
        input signed [W-1:0] task_a0;
        input signed [W-1:0] task_b0;
        input signed [W-1:0] task_a1;
        input signed [W-1:0] task_b1;
        input signed [W-1:0] task_a2;
        input signed [W-1:0] task_b2;
        reg signed [63:0] a0_ext;
        reg signed [63:0] b0_ext;
        reg signed [63:0] a1_ext;
        reg signed [63:0] b1_ext;
        reg signed [63:0] a2_ext;
        reg signed [63:0] b2_ext;
        reg signed [63:0] accumulator_ext;
        reg signed [63:0] rounded_ext;
        reg signed [W-1:0] expected_y;
        reg expected_overflow;
        begin
            mac_a0 = task_a0;
            mac_b0 = task_b0;
            mac_a1 = task_a1;
            mac_b1 = task_b1;
            mac_a2 = task_a2;
            mac_b2 = task_b2;
            #1;
            a0_ext = task_a0;
            b0_ext = task_b0;
            a1_ext = task_a1;
            b1_ext = task_b1;
            a2_ext = task_a2;
            b2_ext = task_b2;
            accumulator_ext = (a0_ext * b0_ext) + (a1_ext * b1_ext) + (a2_ext * b2_ext);
            if (accumulator_ext < 0) begin
                rounded_ext = -(((-accumulator_ext) + TB_HALF) >>> F);
            end else begin
                rounded_ext = (accumulator_ext + TB_HALF) >>> F;
            end
            expected_overflow = 1'b0;
            if (rounded_ext > TB_MAX) begin
                expected_y = TB_MAX_WORD;
                expected_overflow = 1'b1;
            end else if (rounded_ext < -(-TB_MIN)) begin
                expected_y = TB_MIN_WORD;
                expected_overflow = 1'b1;
            end else begin
                expected_y = rounded_ext[W-1:0];
            end
            checks = checks + 1;
            if ((mac_y !== expected_y) || (mac_overflow !== expected_overflow)) begin
                failures = failures + 1;
                $display("MAC mismatch got=%0d ov=%b expected=%0d ov=%b",
                         mac_y, mac_overflow, expected_y, expected_overflow);
            end
        end
    endtask

    initial begin
        failures = 0;
        checks = 0;
        random_seed = 32'h51483136;
        add_a = 0;
        add_b = 0;
        sub_a = 0;
        sub_b = 0;
        mul_a = 0;
        mul_b = 0;
        mac_a0 = 0;
        mac_b0 = 0;
        mac_a1 = 0;
        mac_b1 = 0;
        mac_a2 = 0;
        mac_b2 = 0;

        // Directed add/sub boundary checks.
        check_add(0, 0);
        check_add(TB_MAX_WORD, 0);
        check_add(TB_MAX_WORD, 1);
        check_add(TB_MIN_WORD, -1);
        check_add(TB_MAX_WORD, TB_MIN_WORD);
        check_add(fx_q16(64'sd98304), -TB_HALF);
        check_sub(0, 0);
        check_sub(TB_MAX_WORD, -1);
        check_sub(TB_MIN_WORD, 1);
        check_sub(TB_MIN_WORD, TB_MIN_WORD);
        check_sub(TB_MAX_WORD, TB_MIN_WORD);
        check_sub(fx_q16(64'sd98304), TB_HALF);

        // Directed multiply checks, including both signs of exact half ties.
        check_mul(1, (TB_HALF-1));
        check_mul(1, TB_HALF);
        check_mul(-1, (TB_HALF-1));
        check_mul(-1, TB_HALF);
        check_mul(1, TB_HALF+1);
        check_mul(-1, TB_HALF+1);
        check_mul(fx_q16(64'sd65536), TB_MAX_WORD);
        check_mul(fx_q16(64'sd65536), TB_MIN_WORD);
        check_mul(fx_q16(64'sd98304), fx_q16(64'sd147456));
        check_mul(TB_MAX_WORD, TB_MAX_WORD);
        check_mul(TB_MIN_WORD, TB_MAX_WORD);
        check_mul(TB_MIN_WORD, TB_MIN_WORD);

        // The MAC must sum full products and round only once.
        check_mac(1, TB_HALF,
                  1, TB_HALF,
                  1, TB_HALF);
        check_mac(-1, TB_HALF,
                  -1, TB_HALF,
                  -1, TB_HALF);
        check_mac(fx_q16(64'sd65536), fx_q16(64'sd65536),
                  fx_q16(64'sd131072), fx_q16(64'sd196608),
                  -TB_HALF, fx_q16(64'sd262144));
        check_mac(TB_MAX_WORD, TB_MAX_WORD,
                  TB_MAX_WORD, TB_MAX_WORD,
                  TB_MAX_WORD, TB_MAX_WORD);
        check_mac(TB_MIN_WORD, TB_MAX_WORD,
                  TB_MIN_WORD, TB_MAX_WORD,
                  TB_MIN_WORD, TB_MAX_WORD);

        // Deterministic random regression over the full configured-width input space.
        for (index = 0; index < 2000; index = index + 1) begin
            random_a = $random(random_seed);
            random_b = $random(random_seed);
            random_c = $random(random_seed);
            random_d = $random(random_seed);
            random_e = $random(random_seed);
            random_f = $random(random_seed);
            check_add(random_a, random_b);
            check_sub(random_a, random_b);
            check_mul(random_a, random_b);
            check_mac(random_a, random_b,
                      random_c, random_d,
                      random_e, random_f);
        end

        if (failures == 0) begin
            $display("PASS: q8_16 arithmetic (%0d checks)", checks);
            $finish;
        end else begin
            $display("FAIL: q8_16 arithmetic (%0d failures / %0d checks)", failures, checks);
            $finish_and_return(1);
        end
    end
endmodule

`default_nettype wire
