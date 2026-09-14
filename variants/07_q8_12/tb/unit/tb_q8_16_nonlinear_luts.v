`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/fx_q8_16_defs.vh"

module tb_q8_16_nonlinear_luts;
    `include "tb/unit/fx_format_tb.vh"

    reg clk;

    reg                       rsqrt_en;
    reg  signed [W-1:0]        rsqrt_x;
    wire signed [W-1:0]        rsqrt_y;
    wire                      rsqrt_valid;
    wire                      rsqrt_domain_error;

    reg                       asin_en;
    reg  signed [W-1:0]        asin_x;
    wire signed [W-1:0]        asin_y;
    wire                      asin_valid;
    wire                      asin_domain_error;

    reg signed [W-1:0] rsqrt_reference [0:4095];
    reg signed [W-1:0] asin_reference   [0:4096];
    reg signed [W-1:0] held_value;
    integer errors;

    q8_16_rsqrt_lut u_rsqrt (
        .clk(clk),
        .en(rsqrt_en),
        .x(rsqrt_x),
        .y(rsqrt_y),
        .valid(rsqrt_valid),
        .domain_error(rsqrt_domain_error)
    );

    arcsine_cov_lut_q8_16 u_asin (
        .clk(clk),
        .en(asin_en),
        .x(asin_x),
        .y(asin_y),
        .valid(asin_valid),
        .domain_error(asin_domain_error)
    );

    always #5 clk = ~clk;

    task check_rsqrt;
        input signed [W-1:0] stimulus;
        input integer expected_address;
        input expected_error;
        begin
            @(negedge clk);
            rsqrt_x = stimulus;
            rsqrt_en = 1'b1;
            @(posedge clk);
            #1;
            if (rsqrt_valid !== 1'b1) begin
                $display("FAIL rsqrt valid: x=%0d valid=%b", stimulus, rsqrt_valid);
                errors = errors + 1;
            end
            if (rsqrt_y !== rsqrt_reference[expected_address]) begin
                $display("FAIL rsqrt data: x=%0d address=%0d expected=%0d actual=%0d",
                         stimulus, expected_address,
                         rsqrt_reference[expected_address], rsqrt_y);
                errors = errors + 1;
            end
            if (rsqrt_domain_error !== expected_error) begin
                $display("FAIL rsqrt domain_error: x=%0d expected=%b actual=%b",
                         stimulus, expected_error, rsqrt_domain_error);
                errors = errors + 1;
            end
            held_value = rsqrt_y;
            @(negedge clk);
            rsqrt_en = 1'b0;
            rsqrt_x = 0;
            @(posedge clk);
            #1;
            if (rsqrt_valid !== 1'b0) begin
                $display("FAIL rsqrt idle valid: actual=%b", rsqrt_valid);
                errors = errors + 1;
            end
            if (rsqrt_domain_error !== 1'b0) begin
                $display("FAIL rsqrt idle domain_error: actual=%b", rsqrt_domain_error);
                errors = errors + 1;
            end
            if (rsqrt_y !== held_value) begin
                $display("FAIL rsqrt idle hold: expected=%0d actual=%0d",
                         held_value, rsqrt_y);
                errors = errors + 1;
            end
        end
    endtask

    task check_asin;
        input signed [W-1:0] stimulus;
        input integer expected_address;
        input expected_error;
        begin
            @(negedge clk);
            asin_x = stimulus;
            asin_en = 1'b1;
            @(posedge clk);
            #1;
            if (asin_valid !== 1'b1) begin
                $display("FAIL asin valid: x=%0d valid=%b", stimulus, asin_valid);
                errors = errors + 1;
            end
            if (asin_y !== asin_reference[expected_address]) begin
                $display("FAIL asin data: x=%0d address=%0d expected=%0d actual=%0d",
                         stimulus, expected_address,
                         asin_reference[expected_address], asin_y);
                errors = errors + 1;
            end
            if (asin_domain_error !== expected_error) begin
                $display("FAIL asin domain_error: x=%0d expected=%b actual=%b",
                         stimulus, expected_error, asin_domain_error);
                errors = errors + 1;
            end
            held_value = asin_y;
            @(negedge clk);
            asin_en = 1'b0;
            asin_x = 0;
            @(posedge clk);
            #1;
            if (asin_valid !== 1'b0) begin
                $display("FAIL asin idle valid: actual=%b", asin_valid);
                errors = errors + 1;
            end
            if (asin_domain_error !== 1'b0) begin
                $display("FAIL asin idle domain_error: actual=%b", asin_domain_error);
                errors = errors + 1;
            end
            if (asin_y !== held_value) begin
                $display("FAIL asin idle hold: expected=%0d actual=%0d",
                         held_value, asin_y);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rsqrt_en = 1'b0;
        rsqrt_x = 0;
        asin_en = 1'b0;
        asin_x = 0;
        held_value = 0;
        errors = 0;

        $readmemh("rtl/nonlinear/rsqrt_q16.hex", rsqrt_reference);
        $readmemh("rtl/nonlinear/arcsine_cov_q16.hex", asin_reference);

        if (rsqrt_reference[0] !== $rtoi($sqrt(2048.0)*TB_ONE+0.5) ||
            rsqrt_reference[1] !== $rtoi($sqrt(2048.0/3.0)*TB_ONE+0.5) ||
            rsqrt_reference[4095] !== $rtoi($sqrt(2048.0/8191.0)*TB_ONE+0.5)) begin
            $display("FAIL rsqrt LUT image endpoint constants");
            errors = errors + 1;
        end
        if (asin_reference[0] !== -`FX_Q8_16_ONE ||
            asin_reference[2048] !== 0 ||
            asin_reference[4096] !== `FX_Q8_16_ONE) begin
            $display("FAIL asin LUT image endpoint constants");
            errors = errors + 1;
        end

        /* Prime valid because the leaf interface intentionally has no reset. */
        @(posedge clk);
        #1;
        if (rsqrt_valid !== 1'b0 || asin_valid !== 1'b0) begin
            $display("FAIL idle valid priming: rsqrt=%b asin=%b",
                     rsqrt_valid, asin_valid);
            errors = errors + 1;
        end

        /* Input grid and clamp policies stay fixed in real units. */
        check_rsqrt(TB_MIN_WORD, 1, 1'b1);
        check_rsqrt(-1, 1, 1'b1);
        check_rsqrt(0, 1, 1'b1);
        check_rsqrt(`FX_Q8_16_DIAG_FLOOR-1, 1, 1'b1);
        check_rsqrt(`FX_Q8_16_DIAG_FLOOR, 1, 1'b0);
        check_rsqrt((2 << (F-10))-1, 1, 1'b0);
        check_rsqrt(2 << (F-10), 2, 1'b0);
        check_rsqrt((4095 << (F-10))-1, 4094, 1'b0);
        check_rsqrt(4095 << (F-10), 4095, 1'b0);
        check_rsqrt(4*TB_ONE-1, 4095, 1'b0);
        check_rsqrt(4*TB_ONE, 4095, 1'b0);
        check_rsqrt(TB_MAX_WORD, 4095, 1'b0);

        check_asin(TB_MIN_WORD, 0, 1'b1);
        check_asin(-TB_ONE-1, 0, 1'b1);
        check_asin(-TB_ONE, 0, 1'b0);
        check_asin(-TB_ONE+1, 0, 1'b0);
        check_asin(-TB_ONE+(1 << (F-11))-1, 0, 1'b0);
        check_asin(-TB_ONE+(1 << (F-11)), 1, 1'b0);
        check_asin(-(1 << (F-11)), 2047, 1'b0);
        check_asin(-1, 2047, 1'b0);
        check_asin(0, 2048, 1'b0);
        check_asin((1 << (F-11))-1, 2048, 1'b0);
        check_asin(1 << (F-11), 2049, 1'b0);
        check_asin(TB_ONE-(1 << (F-11))-1, 4094, 1'b0);
        check_asin(TB_ONE-(1 << (F-11)), 4095, 1'b0);
        check_asin(TB_ONE-1, 4095, 1'b0);
        check_asin(TB_ONE, 4096, 1'b0);
        check_asin(TB_ONE+1, 4096, 1'b1);
        check_asin(TB_MAX_WORD, 4096, 1'b1);

        if (errors == 0) begin
            $display("PASS: q8_16 nonlinear LUT endpoint tests");
            $finish;
        end

        $display("FAIL: q8_16 nonlinear LUT endpoint tests (%0d errors)", errors);
        $fatal(1);
    end

endmodule

`default_nettype wire
