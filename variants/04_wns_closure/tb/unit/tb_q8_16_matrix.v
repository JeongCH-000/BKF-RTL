`timescale 1ns/1ps
`default_nettype none

module tb_q8_16_matrix;
    localparam integer MATMUL_CASES = 64;
    localparam integer INVERSE_CASES = 25;

    reg clk;
    reg rst_n;
    reg [215:0] matmul_a;
    reg [215:0] matmul_b;
    wire [215:0] matmul_y;
    wire matmul_overflow;
    reg [215:0] inverse_input;
    reg inverse_start;
    wire inverse_busy;
    wire inverse_valid;
    wire [215:0] inverse_y;
    wire signed [23:0] inverse_determinant;
    wire inverse_solver_error;
    wire inverse_overflow;

    reg [215:0] matmul_a_mem [0:MATMUL_CASES-1];
    reg [215:0] matmul_b_mem [0:MATMUL_CASES-1];
    reg [215:0] matmul_y_mem [0:MATMUL_CASES-1];
    reg [1:0] matmul_flags_mem [0:MATMUL_CASES-1];
    reg [215:0] inverse_input_mem [0:INVERSE_CASES-1];
    reg [215:0] inverse_y_mem [0:INVERSE_CASES-1];
    reg [23:0] inverse_det_mem [0:INVERSE_CASES-1];
    reg [1:0] inverse_flags_mem [0:INVERSE_CASES-1];
    integer index;
    integer checks;

    q8_16_matmul3 u_matmul (
        .a_flat(matmul_a), .b_flat(matmul_b), .y_flat(matmul_y), .overflow(matmul_overflow)
    );

    mat3_inverse_q8_16 u_inverse (
        .clk(clk), .rst_n(rst_n), .start(inverse_start),
        .matrix_flat(inverse_input), .busy(inverse_busy), .valid(inverse_valid), .inverse_flat(inverse_y),
        .determinant(inverse_determinant), .solver_error(inverse_solver_error),
        .overflow(inverse_overflow)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        inverse_start = 1'b0;
        $readmemh("tb/vectors/unit_matmul_a.hex", matmul_a_mem);
        $readmemh("tb/vectors/unit_matmul_b.hex", matmul_b_mem);
        $readmemh("tb/vectors/unit_matmul_y.hex", matmul_y_mem);
        $readmemh("tb/vectors/unit_matmul_flags.hex", matmul_flags_mem);
        $readmemh("tb/vectors/unit_inverse_input.hex", inverse_input_mem);
        $readmemh("tb/vectors/unit_inverse_y.hex", inverse_y_mem);
        $readmemh("tb/vectors/unit_inverse_det.hex", inverse_det_mem);
        $readmemh("tb/vectors/unit_inverse_flags.hex", inverse_flags_mem);
        checks = 0;
        matmul_a = 216'd0;
        matmul_b = 216'd0;
        inverse_input = 216'd0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        for (index = 0; index < MATMUL_CASES; index = index + 1) begin
            matmul_a = matmul_a_mem[index];
            matmul_b = matmul_b_mem[index];
            #1;
            checks = checks + 1;
            if ((matmul_y !== matmul_y_mem[index]) ||
                (matmul_overflow !== matmul_flags_mem[index][0])) begin
                $display("FAIL matmul case=%0d expected_ov=%b actual_ov=%b", index,
                         matmul_flags_mem[index][0], matmul_overflow);
                $fatal(1);
            end
        end

        for (index = 0; index < INVERSE_CASES; index = index + 1) begin
            while (inverse_busy) @(negedge clk);
            inverse_input = inverse_input_mem[index];
            inverse_start = 1'b1;
            @(negedge clk);
            inverse_start = 1'b0;
            while (!inverse_valid) @(negedge clk);
            checks = checks + 1;
            if ((inverse_y !== inverse_y_mem[index]) ||
                ($signed(inverse_determinant) !== $signed(inverse_det_mem[index])) ||
                (inverse_overflow !== inverse_flags_mem[index][0]) ||
                (inverse_solver_error !== inverse_flags_mem[index][1])) begin
                $display("FAIL inverse case=%0d det expected=%0d actual=%0d solver expected=%b actual=%b ov expected=%b actual=%b",
                         index, $signed(inverse_det_mem[index]), inverse_determinant,
                         inverse_flags_mem[index][1], inverse_solver_error,
                         inverse_flags_mem[index][0], inverse_overflow);
                $fatal(1);
            end
        end

        $display("PASS: q8_16 matrix and sequential solver units (%0d checks)", checks);
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: matrix test timeout index=%0d", index);
        $fatal(1);
    end
endmodule

`default_nettype wire
