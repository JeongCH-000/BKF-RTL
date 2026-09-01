`timescale 1ns/1ps
`default_nettype none

module tb_q8_16_nonlinear_luts;

    reg clk;

    reg                       rsqrt_en;
    reg  signed [23:0]        rsqrt_x;
    wire signed [23:0]        rsqrt_y;
    wire                      rsqrt_valid;
    wire                      rsqrt_domain_error;

    reg                       asin_en;
    reg  signed [23:0]        asin_x;
    wire signed [23:0]        asin_y;
    wire                      asin_valid;
    wire                      asin_domain_error;

    reg signed [23:0] rsqrt_reference [0:4095];
    reg signed [23:0] asin_reference   [0:4096];
    reg signed [23:0] held_value;
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
        input signed [23:0] stimulus;
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
            rsqrt_x = 24'sd0;
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
        input signed [23:0] stimulus;
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
            asin_x = 24'sd0;
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
        rsqrt_x = 24'sd0;
        asin_en = 1'b0;
        asin_x = 24'sd0;
        held_value = 24'sd0;
        errors = 0;

        $readmemh("rtl/nonlinear/rsqrt_q16.hex", rsqrt_reference);
        $readmemh("rtl/nonlinear/arcsine_cov_q16.hex", asin_reference);

        if (rsqrt_reference[0] !== 24'sh2d413d ||
            rsqrt_reference[1] !== 24'sh1a20bd ||
            rsqrt_reference[4095] !== 24'sh008002) begin
            $display("FAIL rsqrt LUT image endpoint constants");
            errors = errors + 1;
        end
        if (asin_reference[0] !== 24'shff0000 ||
            asin_reference[2048] !== 24'sh000000 ||
            asin_reference[4096] !== 24'sh010000) begin
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

        /* rsqrt: floor boundary, address-bin boundaries, and upper clamp. */
        check_rsqrt(24'sh800000, 1, 1'b1);
        check_rsqrt(-24'sd1, 1, 1'b1);
        check_rsqrt(24'sd0, 1, 1'b1);
        check_rsqrt(24'sd63, 1, 1'b1);
        check_rsqrt(24'sd64, 1, 1'b0);
        check_rsqrt(24'sd127, 1, 1'b0);
        check_rsqrt(24'sd128, 2, 1'b0);
        check_rsqrt(24'sd262079, 4094, 1'b0);
        check_rsqrt(24'sd262080, 4095, 1'b0);
        check_rsqrt(24'sd262143, 4095, 1'b0);
        check_rsqrt(24'sd262144, 4095, 1'b0);
        check_rsqrt(24'sh7fffff, 4095, 1'b0);

        /* asin: strict domain errors and all clamp/bin endpoints. */
        check_asin(24'sh800000, 0, 1'b1);
        check_asin(-24'sd65537, 0, 1'b1);
        check_asin(-24'sd65536, 0, 1'b0);
        check_asin(-24'sd65535, 0, 1'b0);
        check_asin(-24'sd65505, 0, 1'b0);
        check_asin(-24'sd65504, 1, 1'b0);
        check_asin(-24'sd32, 2047, 1'b0);
        check_asin(-24'sd1, 2047, 1'b0);
        check_asin(24'sd0, 2048, 1'b0);
        check_asin(24'sd31, 2048, 1'b0);
        check_asin(24'sd32, 2049, 1'b0);
        check_asin(24'sd65503, 4094, 1'b0);
        check_asin(24'sd65504, 4095, 1'b0);
        check_asin(24'sd65535, 4095, 1'b0);
        check_asin(24'sd65536, 4096, 1'b0);
        check_asin(24'sd65537, 4096, 1'b1);
        check_asin(24'sh7fffff, 4096, 1'b1);

        if (errors == 0) begin
            $display("PASS: q8_16 nonlinear LUT endpoint tests");
            $finish;
        end

        $display("FAIL: q8_16 nonlinear LUT endpoint tests (%0d errors)", errors);
        $fatal(1);
    end

endmodule

`default_nettype wire
