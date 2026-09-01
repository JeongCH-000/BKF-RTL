`timescale 1ns/1ps
`default_nettype none

module tb_ekf_overflow_pipeline;
    localparam integer RANDOM_SEED = 20260831;
    localparam integer RANDOM_CASES = 2000;
    localparam [5:0] ST_IDLE = 6'd0;
    localparam [5:0] ST_ADD_Q = 6'd4;
    localparam [5:0] ST_XPRED = 6'd1;
    localparam [5:0] ST_RESULT = 6'd29;
    localparam [5:0] ST_ADD_Q_COMMIT = 6'd39;
    localparam [5:0] ST_COV_OUTER_COMMIT = 6'd38;

    localparam signed [63:0] FX_MAX_RAW = 64'sd549755748352;
    localparam signed [63:0] FX_MIN_RAW = -64'sd549755813888;

    reg clk;
    reg rst_n;
    reg cfg_valid;
    wire cfg_ready;
    reg [71:0] cfg_state_flat;
    reg [215:0] cfg_cov_flat;
    reg model_valid;
    wire model_ready;
    reg [215:0] f_input_flat;
    wire threshold_valid;
    reg threshold_ready;
    wire [71:0] threshold_flat;
    reg observation_valid;
    wire observation_ready;
    reg [2:0] observation_flat;
    reg [71:0] measurement_flat;
    wire result_valid;
    reg result_ready;
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

    integer output_file;
    integer error_count;
    integer transaction_count;
    integer directed_count;
    integer randomized_count;
    integer sequence_count;
    integer random_seed;
    integer case_index;
    integer sequence_index;
    integer element_index;
    integer offset_value;
    reg [31:0] random_low;
    reg [31:0] random_high;
    reg signed [49:0] random_accumulator;
    reg signed [63:0] random_wide;
    reg signed [23:0] captured_rounded;
    reg captured_local_valid;
    reg captured_local_overflow;
    reg [5:0] captured_state;
    string output_path;

    bkf_core #(
        .NUM_BRANCHES(1),
        .EKF_MODE(1)
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

    always #5 clk = ~clk;

    function automatic signed [23:0] reference_round_sat50;
        input signed [49:0] value;
        reg signed [50:0] extended_value;
        reg signed [50:0] rounded_value;
        begin
            extended_value = {value[49], value};
            if (extended_value < 0)
                rounded_value = -(((-extended_value) + 51'sd32768) >>> 16);
            else
                rounded_value = (extended_value + 51'sd32768) >>> 16;
            if (rounded_value > 51'sd8388607)
                reference_round_sat50 = 24'sh7fffff;
            else if (rounded_value < -51'sd8388608)
                reference_round_sat50 = 24'sh800000;
            else
                reference_round_sat50 = rounded_value[23:0];
        end
    endfunction

    function automatic reference_overflow50;
        input signed [49:0] value;
        reg signed [50:0] extended_value;
        reg signed [50:0] rounded_value;
        begin
            extended_value = {value[49], value};
            if (extended_value < 0)
                rounded_value = -(((-extended_value) + 51'sd32768) >>> 16);
            else
                rounded_value = (extended_value + 51'sd32768) >>> 16;
            reference_overflow50 = (rounded_value > 51'sd8388607) ||
                                   (rounded_value < -51'sd8388608);
        end
    endfunction

    function automatic [8:0] element_mask;
        input integer index;
        begin
            element_mask = 9'b000000001 << index;
        end
    endfunction

    task automatic check_bit;
        input string description;
        input actual;
        input expected;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s expected=%0b actual=%0b time=%0t", description,
                         expected, actual, $time);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic check_state;
        input string description;
        input [5:0] actual;
        input [5:0] expected;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s expected_state=%0d actual_state=%0d time=%0t",
                         description, expected, actual, $time);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic apply_reset;
        begin
            rst_n = 1'b0;
            cfg_valid = 1'b0;
            model_valid = 1'b0;
            observation_valid = 1'b0;
            repeat (2) @(posedge clk);
            #1;
            check_bit("overflow clear during reset", overflow_flag, 1'b0);
            check_bit("done clear during reset", done, 1'b0);
            check_bit("result_valid clear during reset", result_valid, 1'b0);
`ifdef EKF_OVERFLOW_PIPELINED
            check_bit("local overflow valid clear during reset",
                      dut.cov_predict_overflow_local_valid_reg, 1'b0);
            check_bit("local overflow clear during reset",
                      dut.cov_predict_overflow_local_reg, 1'b0);
`endif
            rst_n = 1'b1;
            @(posedge clk);
            #1;
            check_state("state after reset", fsm_state, ST_IDLE);
        end
    endtask

    task automatic clear_transaction_status;
        begin
            if (fsm_state !== ST_IDLE)
                apply_reset();
            @(negedge clk);
            cfg_valid = 1'b1;
            @(posedge clk);
            #1;
            cfg_valid = 1'b0;
            check_bit("transaction clear overflow", overflow_flag, 1'b0);
            check_bit("transaction clear numeric error", numeric_error, 1'b0);
            check_bit("transaction clear solver error", solver_error, 1'b0);
`ifdef EKF_OVERFLOW_PIPELINED
            check_bit("transaction clear local valid",
                      dut.cov_predict_overflow_local_valid_reg, 1'b0);
`endif
        end
    endtask

    task automatic inject_and_record;
        input string test_class;
        input string case_name;
        input integer sequence_number;
        input integer matrix_element;
        input last_element;
        input special_commit_state;
        input signed [49:0] accumulator;
        input sticky_before;
        reg signed [23:0] expected_rounded;
        reg expected_overflow;
        reg expected_sticky;
        reg signed [23:0] observed_rounded;
        reg observed_sticky;
        integer sticky_latency;
        begin
            expected_rounded = reference_round_sat50(accumulator);
            expected_overflow = reference_overflow50(accumulator);
            expected_sticky = sticky_before | expected_overflow;

            @(negedge clk);
            dut.state = special_commit_state ? ST_COV_OUTER_COMMIT : ST_IDLE;
            dut.cov_predict_mac_accumulator_reg = accumulator;
            dut.cov_predict_mac_write_mask_reg = element_mask(matrix_element);
            dut.cov_predict_mac_row_reg = matrix_element / 3;
            dut.cov_predict_mac_col_reg = matrix_element % 3;
            dut.cov_predict_mac_last_reg = last_element;
            dut.cov_predict_mac_valid = 1'b1;

            @(posedge clk);
            #1;
            observed_rounded = dut.cov_predict[matrix_element];
            captured_state = fsm_state;
            if (observed_rounded !== expected_rounded) begin
                $display("FAIL: round/saturation case=%0s acc=%0d expected=%0d actual=%0d",
                         case_name, accumulator, expected_rounded, observed_rounded);
                error_count = error_count + 1;
            end
            if ((^observed_rounded) === 1'bx) begin
                $display("FAIL: X/Z rounded output case=%0s", case_name);
                error_count = error_count + 1;
            end
            check_bit("done before overflow commit", done, 1'b0);
            check_bit("result_valid before overflow commit", result_valid, 1'b0);

`ifdef EKF_OVERFLOW_PIPELINED
            captured_local_valid = dut.cov_predict_overflow_local_valid_reg;
            captured_local_overflow = dut.cov_predict_overflow_local_reg;
            check_bit("local overflow valid at capture", captured_local_valid, 1'b1);
            check_bit("local overflow candidate", captured_local_overflow,
                      expected_overflow);
            check_bit("sticky unchanged at local capture", overflow_flag,
                      sticky_before);
            sticky_latency = 1;
`else
            captured_local_valid = 1'b0;
            captured_local_overflow = 1'b0;
            check_bit("baseline immediate sticky", overflow_flag, expected_sticky);
            sticky_latency = 0;
`endif

            if (special_commit_state)
                check_state("last element advances before sticky commit",
                            captured_state, ST_ADD_Q);

            dut.cov_predict_mac_valid = 1'b0;
            dut.cov_predict_mac_write_mask_reg = 9'd0;
            @(posedge clk);
            #1;
`ifdef EKF_OVERFLOW_PIPELINED
            check_bit("current delayed sticky", overflow_flag, expected_sticky);
            check_bit("local overflow valid consumed",
                      dut.cov_predict_overflow_local_valid_reg, 1'b0);
`else
            check_bit("baseline sticky hold", overflow_flag, expected_sticky);
`endif
            check_bit("done at sticky observation", done, 1'b0);
            check_bit("result_valid at sticky observation", result_valid, 1'b0);
            if (special_commit_state)
                check_state("last element downstream state at sticky commit",
                            fsm_state, ST_ADD_Q_COMMIT);

            observed_sticky = overflow_flag;
            $fdisplay(output_file,
                "%0d,%0s,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                transaction_count, test_class, case_name, sequence_number,
                matrix_element, last_element, accumulator, expected_rounded,
                expected_overflow, expected_sticky, observed_rounded,
                observed_sticky, captured_local_valid, sticky_latency);
            transaction_count = transaction_count + 1;
        end
    endtask

    task automatic run_independent;
        input string test_class;
        input string case_name;
        input signed [49:0] accumulator;
        input integer matrix_element;
        begin
            clear_transaction_status();
            inject_and_record(test_class, case_name, 0, matrix_element,
                              (matrix_element == 8), 1'b0, accumulator, 1'b0);
        end
    endtask

    task automatic run_sticky_sequence;
        input string case_name;
        input integer overflow_pattern;
        reg sticky_expected;
        reg signed [49:0] sequence_accumulator;
        begin
            clear_transaction_status();
            sticky_expected = 1'b0;
            for (sequence_index = 0; sequence_index < 9;
                 sequence_index = sequence_index + 1) begin
                if ((overflow_pattern & (1 << sequence_index)) != 0)
                    sequence_accumulator = FX_MAX_RAW + 64'sd65536;
                else
                    sequence_accumulator = (sequence_index - 4) * 64'sd65536;
                inject_and_record("sticky", case_name, sequence_index,
                                  sequence_index, (sequence_index == 8), 1'b0,
                                  sequence_accumulator, sticky_expected);
                sticky_expected = sticky_expected |
                                  reference_overflow50(sequence_accumulator);
            end
            check_bit("sticky sequence final value", overflow_flag,
                      (overflow_pattern != 0));
            sequence_count = sequence_count + 1;
        end
    endtask

    task automatic run_last_element_commit;
        begin
            clear_transaction_status();
            inject_and_record("control", "last_element_commit", 8, 8, 1'b1,
                              1'b1, FX_MAX_RAW + 64'sd65536, 1'b0);
            check_bit("last element overflow retained", overflow_flag, 1'b1);
            apply_reset();
        end
    endtask

    task automatic run_pending_reset_flush;
        reg signed [49:0] accumulator;
        reg signed [23:0] expected_rounded;
        reg expected_overflow;
        reg baseline_capture_sticky;
        begin
            clear_transaction_status();
            accumulator = FX_MIN_RAW - 64'sd65536;
            expected_rounded = reference_round_sat50(accumulator);
            expected_overflow = reference_overflow50(accumulator);

            @(negedge clk);
            dut.state = ST_IDLE;
            dut.cov_predict_mac_accumulator_reg = accumulator;
            dut.cov_predict_mac_write_mask_reg = 9'b000000001;
            dut.cov_predict_mac_row_reg = 2'd0;
            dut.cov_predict_mac_col_reg = 2'd0;
            dut.cov_predict_mac_last_reg = 1'b0;
            dut.cov_predict_mac_valid = 1'b1;
            @(posedge clk);
            #1;
            captured_rounded = dut.cov_predict[0];
            baseline_capture_sticky = overflow_flag;
            if (captured_rounded !== expected_rounded) begin
                $display("FAIL: reset-flush rounded result expected=%0d actual=%0d",
                         expected_rounded, captured_rounded);
                error_count = error_count + 1;
            end
`ifdef EKF_OVERFLOW_PIPELINED
            captured_local_valid = dut.cov_predict_overflow_local_valid_reg;
            captured_local_overflow = dut.cov_predict_overflow_local_reg;
            check_bit("reset-flush local valid before reset",
                      captured_local_valid, 1'b1);
            check_bit("reset-flush local overflow before reset",
                      captured_local_overflow, 1'b1);
            check_bit("reset-flush sticky pending before reset",
                      overflow_flag, 1'b0);
`else
            captured_local_valid = 1'b0;
            captured_local_overflow = 1'b0;
            check_bit("reset-flush baseline immediate sticky",
                      baseline_capture_sticky, 1'b1);
`endif
            dut.cov_predict_mac_valid = 1'b0;
            rst_n = 1'b0;
            #1;
            check_bit("reset flushes sticky", overflow_flag, 1'b0);
            check_bit("reset suppresses done", done, 1'b0);
            check_bit("reset suppresses result_valid", result_valid, 1'b0);
`ifdef EKF_OVERFLOW_PIPELINED
            check_bit("reset flushes pending valid",
                      dut.cov_predict_overflow_local_valid_reg, 1'b0);
            check_bit("reset flushes pending overflow",
                      dut.cov_predict_overflow_local_reg, 1'b0);
`endif
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
            #1;
            check_bit("no sticky leak after reset", overflow_flag, 1'b0);

            $fdisplay(output_file,
                "%0d,control,mid_pending_reset_flush,0,0,0,%0d,%0d,%0d,0,%0d,%0d,%0d,-1",
                transaction_count, accumulator, expected_rounded,
                expected_overflow, captured_rounded, overflow_flag,
                captured_local_valid);
            transaction_count = transaction_count + 1;
        end
    endtask

    task automatic run_busy_start_ignored;
        begin
            clear_transaction_status();
            f_input_flat = {9{24'h012345}};
            @(negedge clk);
            dut.state = ST_ADD_Q;
            model_valid = 1'b1;
            #1;
            check_bit("busy start model_ready", model_ready, 1'b0);
            check_bit("busy start busy", busy, 1'b1);
            @(posedge clk);
            #1;
            model_valid = 1'b0;
            check_state("busy start did not enter prediction", fsm_state,
                        ST_ADD_Q_COMMIT);
            if (fsm_state === ST_XPRED) begin
                $display("FAIL: busy input pulse was accepted");
                error_count = error_count + 1;
            end
            if (dut.f_matrix[0] !== 24'sd0) begin
                $display("FAIL: busy input pulse changed f_matrix");
                error_count = error_count + 1;
            end
            check_bit("busy start overflow unchanged", overflow_flag, 1'b0);
            check_bit("busy start solver unchanged", solver_error, 1'b0);
            $fdisplay(output_file,
                "%0d,control,busy_start_ignored,0,0,0,0,0,0,0,0,%0d,0,-1",
                transaction_count, overflow_flag);
            transaction_count = transaction_count + 1;
            apply_reset();
        end
    endtask

    task automatic run_result_alignment;
        begin
            clear_transaction_status();
            inject_and_record("control", "result_alignment_source", 0, 8,
                              1'b1, 1'b0,
                              FX_MAX_RAW + 64'sd65536, 1'b0);
            @(negedge clk);
            dut.state = ST_RESULT;
            result_ready = 1'b0;
            #1;
            check_bit("result backpressure valid", result_valid, 1'b1);
            check_bit("result backpressure done", done, 1'b0);
            check_bit("result backpressure busy", busy, 1'b1);
            check_bit("result backpressure overflow", overflow_flag, 1'b1);
            check_bit("result backpressure solver", solver_error, 1'b0);
`ifdef EKF_OVERFLOW_PIPELINED
            check_bit("result backpressure local valid drained",
                      dut.cov_predict_overflow_local_valid_reg, 1'b0);
`endif
            repeat (2) begin
                @(posedge clk);
                #1;
                check_bit("result hold valid", result_valid, 1'b1);
                check_bit("result hold overflow", overflow_flag, 1'b1);
                check_bit("result hold solver", solver_error, 1'b0);
            end
            @(negedge clk);
            result_ready = 1'b1;
            #1;
            check_bit("done aligns with final overflow", done, 1'b1);
            check_bit("done cycle final overflow", overflow_flag, 1'b1);
            @(posedge clk);
            #1;
            check_state("result handshake returns idle", fsm_state, ST_IDLE);
            check_bit("overflow persists until next accepted transaction",
                      overflow_flag, 1'b1);
            $fdisplay(output_file,
                "%0d,control,result_backpressure_done,0,8,1,0,0,0,1,0,%0d,0,-1",
                transaction_count, overflow_flag);
            transaction_count = transaction_count + 1;
            apply_reset();
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cfg_valid = 1'b0;
        cfg_state_flat = 72'd0;
        cfg_cov_flat = 216'd0;
        model_valid = 1'b0;
        f_input_flat = 216'd0;
        threshold_ready = 1'b1;
        observation_valid = 1'b0;
        observation_flat = 3'd0;
        measurement_flat = 72'd0;
        result_ready = 1'b1;
        error_count = 0;
        transaction_count = 0;
        directed_count = 0;
        randomized_count = 0;
        sequence_count = 0;
        random_seed = RANDOM_SEED;

        if (!$value$plusargs("OUTPUT=%s", output_path))
            output_path = "results/ekf_overflow_transactions.csv";
        output_file = $fopen(output_path, "w");
        if (output_file == 0)
            $fatal(1, "cannot open output CSV: %0s", output_path);
        $fdisplay(output_file,
            "transaction,test_class,case_name,sequence_index,element_index,last_element,accumulator,expected_rounded,expected_overflow,expected_sticky,observed_rounded,observed_sticky,local_valid_observed,sticky_latency_cycles");

        apply_reset();

        run_independent("directed", "zero", 50'sd0, 0);
        run_independent("directed", "positive_one_raw", 50'sd1, 1);
        run_independent("directed", "negative_one_raw", -50'sd1, 2);
        run_independent("directed", "exact_max", FX_MAX_RAW, 3);
        run_independent("directed", "max_minus_one_output_lsb",
                        FX_MAX_RAW - 64'sd65536, 4);
        run_independent("directed", "max_plus_one_output_lsb",
                        FX_MAX_RAW + 64'sd65536, 5);
        run_independent("directed", "exact_min", FX_MIN_RAW, 6);
        run_independent("directed", "min_plus_one_output_lsb",
                        FX_MIN_RAW + 64'sd65536, 7);
        run_independent("directed", "min_minus_one_output_lsb",
                        FX_MIN_RAW - 64'sd65536, 8);
        run_independent("directed", "positive_round_zero_below", 50'sd32767, 0);
        run_independent("directed", "positive_round_zero_cutoff", 50'sd32768, 1);
        run_independent("directed", "positive_round_zero_above", 50'sd32769, 2);
        run_independent("directed", "negative_round_zero_above", -50'sd32767, 3);
        run_independent("directed", "negative_round_zero_cutoff", -50'sd32768, 4);
        run_independent("directed", "negative_round_zero_below", -50'sd32769, 5);
        run_independent("directed", "positive_overflow_cutoff_below",
                        FX_MAX_RAW + 64'sd32767, 6);
        run_independent("directed", "positive_overflow_cutoff",
                        FX_MAX_RAW + 64'sd32768, 7);
        run_independent("directed", "positive_overflow_cutoff_above",
                        FX_MAX_RAW + 64'sd32769, 8);
        run_independent("directed", "negative_overflow_cutoff_above",
                        FX_MIN_RAW - 64'sd32767, 0);
        run_independent("directed", "negative_overflow_cutoff",
                        FX_MIN_RAW - 64'sd32768, 1);
        run_independent("directed", "negative_overflow_cutoff_below",
                        FX_MIN_RAW - 64'sd32769, 2);
        directed_count = 21;

        for (case_index = 0; case_index < RANDOM_CASES;
             case_index = case_index + 1) begin
            random_low = $urandom(random_seed);
            random_high = $urandom(random_seed);
            case (case_index % 4)
                0: begin
                    random_accumulator = {random_high[17:0], random_low};
                end
                1: begin
                    offset_value = random_low % 131073;
                    offset_value = offset_value - 65536;
                    random_wide = FX_MAX_RAW + offset_value;
                    random_accumulator = random_wide[49:0];
                end
                2: begin
                    offset_value = random_low % 131073;
                    offset_value = offset_value - 65536;
                    random_wide = FX_MIN_RAW + offset_value;
                    random_accumulator = random_wide[49:0];
                end
                default: begin
                    random_wide = $signed(random_low[23:0]);
                    random_wide = (random_wide * 64'sd65536) +
                                  $signed({1'b0, random_high[14:0]});
                    random_accumulator = random_wide[49:0];
                end
            endcase
            run_independent("randomized", "fixed_seed_random", random_accumulator,
                            case_index % 9);
            randomized_count = randomized_count + 1;
        end

        run_sticky_sequence("first_only", 9'b000000001);
        run_sticky_sequence("middle_only", 9'b000010000);
        run_sticky_sequence("last_only", 9'b100000000);
        run_sticky_sequence("multiple", 9'b100010001);
        run_sticky_sequence("none", 9'b000000000);

        run_last_element_commit();
        run_pending_reset_flush();
        run_busy_start_ignored();
        run_result_alignment();

        clear_transaction_status();
        inject_and_record("control", "clear_no_leak_overflow", 0, 0, 1'b0,
                          1'b0, FX_MAX_RAW + 64'sd65536, 1'b0);
        clear_transaction_status();
        inject_and_record("control", "clear_no_leak_following_clean", 1, 1, 1'b0,
                          1'b0, 50'sd0, 1'b0);
        check_bit("overflow does not leak into clean transaction", overflow_flag, 1'b0);

        $fclose(output_file);
        if (randomized_count != RANDOM_CASES) begin
            $display("FAIL: randomized count expected=%0d actual=%0d",
                     RANDOM_CASES, randomized_count);
            error_count = error_count + 1;
        end
        if (error_count != 0)
            $fatal(1,
                "EKF overflow pipeline regression failed errors=%0d transactions=%0d",
                error_count, transaction_count);

`ifdef EKF_OVERFLOW_PIPELINED
        $display("PASS: current EKF overflow pipeline seed=%0d directed=%0d randomized=%0d sticky_sequences=%0d transactions=%0d",
                 RANDOM_SEED, directed_count, randomized_count, sequence_count,
                 transaction_count);
`else
        $display("PASS: baseline EKF overflow behavior seed=%0d directed=%0d randomized=%0d sticky_sequences=%0d transactions=%0d",
                 RANDOM_SEED, directed_count, randomized_count, sequence_count,
                 transaction_count);
`endif
        $finish;
    end

endmodule

`default_nettype wire
