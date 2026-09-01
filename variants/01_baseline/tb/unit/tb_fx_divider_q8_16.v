`timescale 1ns/1ps
`default_nettype none

module tb_fx_divider_q8_16;
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
    integer checks;
    integer index;
    reg signed [23:0] expected;
    reg expected_overflow;

    fx_divider_q8_16 dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .numerator(numerator), .denominator(denominator),
        .busy(busy), .valid(valid), .quotient(quotient),
        .divide_by_zero(divide_by_zero), .overflow(overflow)
    );

    always #5 clk = ~clk;

    function signed [23:0] reference_divide;
        input signed [23:0] n;
        input signed [23:0] d;
        reg signed [24:0] n_ext;
        reg signed [24:0] d_ext;
        reg [24:0] n_mag;
        reg [24:0] d_mag;
        reg [40:0] value;
        reg [41:0] q_mag;
        reg negative;
        begin
            n_ext = {n[23], n};
            d_ext = {d[23], d};
            n_mag = n[23] ? -n_ext : n_ext;
            d_mag = d[23] ? -d_ext : d_ext;
            negative = n[23] ^ d[23];
            if (d_mag == 0)
                reference_divide = n[23] ? 24'sh800000 : 24'sh7fffff;
            else begin
                value = {n_mag, 16'd0};
                q_mag = (value + (d_mag >> 1)) / d_mag;
                if (q_mag > 42'd8388607)
                    reference_divide = negative ? 24'sh800000 : 24'sh7fffff;
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
        reg [40:0] value;
        reg [41:0] q_mag;
        begin
            n_ext = {n[23], n};
            d_ext = {d[23], d};
            n_mag = n[23] ? -n_ext : n_ext;
            d_mag = d[23] ? -d_ext : d_ext;
            if (d_mag == 0)
                reference_overflow = 1'b1;
            else begin
                value = {n_mag, 16'd0};
                q_mag = (value + (d_mag >> 1)) / d_mag;
                reference_overflow = ((!(n[23] ^ d[23])) && (q_mag > 42'd8388607)) ||
                                     ((n[23] ^ d[23]) && (q_mag > 42'd8388608));
            end
        end
    endfunction

    task run_case;
        input signed [23:0] n;
        input signed [23:0] d;
        begin
            while (busy) @(negedge clk);
            numerator = n;
            denominator = d;
            expected = reference_divide(n, d);
            expected_overflow = reference_overflow(n, d);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            while (!valid) @(negedge clk);
            if (($signed(quotient) !== $signed(expected)) ||
                (divide_by_zero !== (d == 0)) ||
                (overflow !== expected_overflow)) begin
                $display("FAIL divider n=%0d d=%0d exp=%0d got=%0d div0=%0d ovf=%0d",
                         n, d, expected, quotient, divide_by_zero, overflow);
                $fatal(1);
            end
            checks = checks + 1;
            @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        numerator = 24'sd0;
        denominator = 24'sd0;
        checks = 0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        run_case(24'sd65536, 24'sd65536);
        run_case(-24'sd65536, 24'sd131072);
        run_case(24'sd1, 24'sd131072);
        run_case(-24'sd1, 24'sd131072);
        run_case(24'sd6554, 24'sd19661);
        run_case(24'sh800000, 24'sd65536);
        run_case(24'sh7fffff, 24'sd65536);
        run_case(24'sd8388607, 24'sd1);
        run_case(-24'sd8388607, 24'sd1);
        run_case(24'sd1234, 24'sd0);
        run_case(-24'sd1234, 24'sd0);
        for (index = 0; index < 32; index = index + 1)
            run_case($random, ($random | 24'sd1));
        $display("PASS: sequential Q8.16 divider (%0d checks)", checks);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: divider timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
