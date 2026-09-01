`timescale 1ns/1ps
`default_nettype none

module tb_wns_equivalence #(
    parameter integer EKF_MODE = 0,
    parameter integer NUM_BRANCHES = 1
);
    localparam integer STEPS = 500;
    localparam integer OBS_WIDTH = 3 * NUM_BRANCHES;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg cfg_valid = 1'b0;
    wire cfg_ready;
    reg [71:0] cfg_state_flat = 72'd0;
    reg [215:0] cfg_cov_flat = 216'd0;
    reg model_valid = 1'b0;
    wire model_ready;
    reg [215:0] f_input_flat = 216'd0;
    wire threshold_valid;
    reg threshold_ready = 1'b1;
    wire [71:0] threshold_flat;
    reg observation_valid = 1'b0;
    wire observation_ready;
    reg [OBS_WIDTH-1:0] observation_flat = {OBS_WIDTH{1'b0}};
    reg [71:0] measurement_flat = 72'd0;
    wire result_valid;
    reg result_ready = 1'b1;
    wire [71:0] state_out_flat;
    wire [215:0] cov_out_flat;
    wire busy;
    wire done;
    wire overflow_flag;
    wire numeric_error;
    wire solver_error;
    wire [5:0] fsm_state;
    wire [215:0] debug_cov_predict_flat;
    wire [215:0] debug_sign_cov_flat;
    wire [215:0] debug_gain_flat;
    wire signed [23:0] debug_determinant;
    wire [71:0] debug_reduced_observation_flat;
    wire [47:0] debug_branch_sum_flat;

    wire [71:0] state_post_trace;
    wire [215:0] cov_post_trace;
    wire [215:0] f_matrix_trace;
    wire [215:0] cov_inner_trace;
    wire [215:0] cov_predict_trace;
    wire [215:0] measurement_cov_trace;
    wire [215:0] sign_cov_trace;
    wire [215:0] gain_trace;
    wire [71:0] observation_q_trace;
    wire [47:0] branch_sum_trace;
    wire [23:0] input_branch_bits_trace;

    reg [71:0] init_state [0:0];
    reg [215:0] init_cov [0:0];
    reg [215:0] f_mem [0:STEPS-1];
    reg [71:0] measurement_mem [0:STEPS-1];
    reg [OBS_WIDTH-1:0] observation_mem [0:STEPS-1];

    reg [8*512-1:0] output_path;
    integer trace_file;
    integer step;
    integer requested_steps;
    integer vector_set_rbkf;
    integer accepted_count;
    integer completed_count;

    always #5 clk = ~clk;

    genvar vector_index;
    generate
        for (vector_index = 0; vector_index < 3; vector_index = vector_index + 1) begin : PACK_VECTOR_TRACE
            assign state_post_trace[(vector_index*24) +: 24] = dut.state_post[vector_index];
            assign observation_q_trace[(vector_index*24) +: 24] = dut.observation_q[vector_index];
        end
    endgenerate

    // EKF has no branch observation transaction. For BKF/rBKF the input bits
    // remain stable through result_valid, so the baseline live debug port and
    // the current transaction-held debug port represent the same branch sums.
    assign branch_sum_trace = (EKF_MODE != 0) ? 48'd0 : debug_branch_sum_flat;

    genvar matrix_index;
    generate
        for (matrix_index = 0; matrix_index < 9; matrix_index = matrix_index + 1) begin : PACK_MATRIX_TRACE
            assign cov_post_trace[(matrix_index*24) +: 24] = dut.cov_post[matrix_index];
            assign f_matrix_trace[(matrix_index*24) +: 24] = dut.f_matrix[matrix_index];
            assign cov_inner_trace[(matrix_index*24) +: 24] = dut.matrix_temp[matrix_index];
            assign cov_predict_trace[(matrix_index*24) +: 24] = dut.cov_predict[matrix_index];
            assign measurement_cov_trace[(matrix_index*24) +: 24] = dut.measurement_cov[matrix_index];
            assign sign_cov_trace[(matrix_index*24) +: 24] = dut.sign_cov[matrix_index];
            assign gain_trace[(matrix_index*24) +: 24] = dut.gain[matrix_index];
        end
    endgenerate

    generate
        if (OBS_WIDTH < 24) begin : PAD_BRANCH_BITS
            assign input_branch_bits_trace = {{(24-OBS_WIDTH){1'b0}}, observation_flat};
        end else begin : KEEP_BRANCH_BITS
            assign input_branch_bits_trace = observation_flat[23:0];
        end
    endgenerate

    bkf_core #(
        .NUM_BRANCHES(NUM_BRANCHES),
        .EKF_MODE(EKF_MODE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_valid(cfg_valid),
        .cfg_ready(cfg_ready),
        .cfg_state_flat(cfg_state_flat),
        .cfg_cov_flat(cfg_cov_flat),
        .model_valid(model_valid),
        .model_ready(model_ready),
        .f_input_flat(f_input_flat),
        .threshold_valid(threshold_valid),
        .threshold_ready(threshold_ready),
        .threshold_flat(threshold_flat),
        .observation_valid(observation_valid),
        .observation_ready(observation_ready),
        .observation_flat(observation_flat),
        .measurement_flat(measurement_flat),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .state_out_flat(state_out_flat),
        .cov_out_flat(cov_out_flat),
        .busy(busy),
        .done(done),
        .overflow_flag(overflow_flag),
        .numeric_error(numeric_error),
        .solver_error(solver_error),
        .fsm_state(fsm_state),
        .debug_cov_predict_flat(debug_cov_predict_flat),
        .debug_sign_cov_flat(debug_sign_cov_flat),
        .debug_gain_flat(debug_gain_flat),
        .debug_determinant(debug_determinant),
        .debug_reduced_observation_flat(debug_reduced_observation_flat),
        .debug_branch_sum_flat(debug_branch_sum_flat)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            accepted_count <= 0;
            completed_count <= 0;
        end else begin
            if (model_valid && model_ready)
                accepted_count <= accepted_count + 1;
            if (result_valid && result_ready)
                completed_count <= completed_count + 1;
        end
    end

    task fail;
        input [8*64-1:0] message;
        begin
            $display(
                "FAIL: WNS equivalence EKF_MODE=%0d NUM_BRANCHES=%0d step=%0d state=%0d %0s",
                EKF_MODE, NUM_BRANCHES, step, fsm_state, message
            );
            $fatal(1);
        end
    endtask

    initial begin
        requested_steps = STEPS;
        vector_set_rbkf = 0;
        accepted_count = 0;
        completed_count = 0;
        if (!$value$plusargs("OUTPUT=%s", output_path))
            fail("missing +OUTPUT=<trace.csv>");
        if (!$value$plusargs("STEPS=%d", requested_steps))
            requested_steps = STEPS;
        if (!$value$plusargs("RBKF_VECTOR_SET=%d", vector_set_rbkf))
            vector_set_rbkf = 0;
        if ((requested_steps < 1) || (requested_steps > STEPS))
            fail("STEPS must be in [1,500]");

        $readmemh("vectors/nominal/common/init_state.mem", init_state);
        $readmemh("vectors/nominal/common/init_cov.mem", init_cov);
        if (EKF_MODE != 0) begin
            $readmemh("vectors/nominal/ekf/f_matrix.mem", f_mem);
            $readmemh("vectors/nominal/ekf/measurement.mem", measurement_mem);
        end else if (NUM_BRANCHES == 8) begin
            $readmemh("vectors/nominal/rbkf_l8/f_matrix.mem", f_mem);
            $readmemh("vectors/nominal/rbkf_l8/branch_observation_bits.mem", observation_mem);
        end else if (vector_set_rbkf != 0) begin
            $readmemh("vectors/nominal/rbkf_l1/f_matrix.mem", f_mem);
            $readmemh("vectors/nominal/rbkf_l1/branch_observation_bits.mem", observation_mem);
        end else begin
            $readmemh("vectors/nominal/bkf_l1/f_matrix.mem", f_mem);
            $readmemh("vectors/nominal/bkf_l1/branch_observation_bits.mem", observation_mem);
        end

        trace_file = $fopen(output_path, "w");
        if (trace_file == 0)
            fail("cannot open output trace");
        $fdisplay(
            trace_file,
            "step,state_post_hex,cov_post_hex,f_matrix_hex,cov_inner_hex,cov_predict_hex,measurement_cov_hex,sign_cov_hex,gain_hex,determinant_hex,observation_q_hex,input_branch_bits_hex,branch_sum_hex,branch_sum_0_int,branch_sum_1_int,branch_sum_2_int,overflow_flag,numeric_error,solver_error"
        );

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        cfg_state_flat = init_state[0];
        cfg_cov_flat = init_cov[0];
        cfg_valid = 1'b1;
        @(negedge clk);
        cfg_valid = 1'b0;

        for (step = 0; step < requested_steps; step = step + 1) begin
            while (!model_ready)
                @(negedge clk);
            f_input_flat = f_mem[step];
            if (EKF_MODE != 0)
                measurement_flat = measurement_mem[step];
            model_valid = 1'b1;
            @(negedge clk);
            model_valid = 1'b0;

            if (EKF_MODE == 0) begin
                while (!threshold_valid)
                    @(negedge clk);
                @(negedge clk);
                while (!observation_ready)
                    @(negedge clk);
                observation_flat = observation_mem[step];
                observation_valid = 1'b1;
                @(negedge clk);
                observation_valid = 1'b0;
            end

            while (!result_valid)
                @(negedge clk);
            if (^state_post_trace === 1'bx) fail("state_post trace contains X/Z");
            if (^cov_post_trace === 1'bx) fail("cov_post trace contains X/Z");
            if (^f_matrix_trace === 1'bx) fail("f_matrix trace contains X/Z");
            if (^cov_inner_trace === 1'bx) fail("cov_inner trace contains X/Z");
            if (^cov_predict_trace === 1'bx) fail("cov_predict trace contains X/Z");
            if (^measurement_cov_trace === 1'bx) fail("measurement_cov trace contains X/Z");
            if (^sign_cov_trace === 1'bx) fail("sign_cov trace contains X/Z");
            if (^gain_trace === 1'bx) fail("gain trace contains X/Z");
            if (^observation_q_trace === 1'bx) fail("observation_q trace contains X/Z");
            if (^branch_sum_trace === 1'bx) fail("branch_sum trace contains X/Z");
            if (^debug_determinant === 1'bx) fail("determinant trace contains X/Z");
            $fdisplay(
                trace_file,
                "%0d,%018h,%054h,%054h,%054h,%054h,%054h,%054h,%054h,%06h,%018h,%06h,%012h,%0d,%0d,%0d,%0d,%0d,%0d",
                step,
                state_post_trace,
                cov_post_trace,
                f_matrix_trace,
                cov_inner_trace,
                cov_predict_trace,
                measurement_cov_trace,
                sign_cov_trace,
                gain_trace,
                debug_determinant,
                observation_q_trace,
                input_branch_bits_trace,
                branch_sum_trace,
                $signed(branch_sum_trace[15:0]),
                $signed(branch_sum_trace[31:16]),
                $signed(branch_sum_trace[47:32]),
                overflow_flag,
                numeric_error,
                solver_error
            );
            @(negedge clk);
        end

        $fclose(trace_file);
        if ((accepted_count != requested_steps) || (completed_count != requested_steps))
            fail("accepted/completed transaction count mismatch");
        $display(
            "PASS: WNS equivalence trace EKF_MODE=%0d NUM_BRANCHES=%0d steps=%0d",
            EKF_MODE, NUM_BRANCHES, requested_steps
        );
        $finish;
    end

    initial begin
        #20000000;
        fail("timeout");
    end
endmodule

`default_nettype wire
