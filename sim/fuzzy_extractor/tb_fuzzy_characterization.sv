`timescale 1ns / 1ps

// Digital BCH/root-recovery coverage. This cannot model physical PUF noise.
// Keep expected enrollment keys in the testbench: decoder success alone does
// not prove that reconstruction returned the originally enrolled root.
module tb_fuzzy_characterization;
    localparam int N = 264;
    localparam int K = 192;
    localparam int PARITY_BITS = N - K;
    localparam int OP_TIMEOUT = 10000;
    localparam int SAMPLES_PER_WEIGHT = 128;

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;
    logic start = 0;
    logic mode = 0;
    logic [N-1:0] response_in = '0;
    logic [N-1:0] helper_in = '0;
    logic [N-1:0] helper_out;
    logic [K-1:0] key_out;
    logic busy, done, success;

    fuzzy_extractor dut (.*);

    logic [31:0] rng = 32'h524f5055;
    logic [N-1:0] reference_response;
    logic [N-1:0] reference_helper;
    logic [K-1:0] reference_key;
    logic [N-1:0] sample_response, sample_helper, error_mask;
    logic [N-1:0] alternate_response, alternate_helper, codeword_delta;
    int failures = 0;
    int checks = 0;
    int operations = 0;
    int corrected_cases = 0;

    initial begin
        repeat (30000000) @(posedge clk);
        $fatal(1, "FE_CHARACTERIZATION_TIMEOUT");
    end

    function automatic logic [31:0] next_random(input logic [31:0] value);
        value = value ^ (value << 13);
        value = value ^ (value >> 17);
        return value ^ (value << 5);
    endfunction

    task automatic random_response(output logic [N-1:0] value);
        for (int bit_index = 0; bit_index < N; bit_index++) begin
            rng = next_random(rng);
            value[bit_index] = rng[0];
        end
    endtask

    // category 0=data only, 1=parity only, 2=mixed (both when weight>=2).
    // Sampling without replacement guarantees the requested Hamming weight.
    task automatic make_error_mask(
        input int weight, input int category, output logic [N-1:0] mask
    );
        int position;
        int inserted;
        mask = '0;
        inserted = 0;
        if (category == 2 && weight >= 2) begin
            rng = next_random(rng);
            mask[PARITY_BITS + (rng % K)] = 1'b1;
            rng = next_random(rng);
            mask[rng % PARITY_BITS] = 1'b1;
            inserted = 2;
        end
        while (inserted < weight) begin
            rng = next_random(rng);
            case (category)
                0: position = PARITY_BITS + (rng % K);
                1: position = rng % PARITY_BITS;
                default: position = rng % N;
            endcase
            if (!mask[position]) begin
                mask[position] = 1'b1;
                inserted++;
            end
        end
    endtask

    task automatic check(input string name, input logic condition);
        checks++;
        if (condition !== 1'b1) begin
            failures++;
            $display("FAIL: %s", name);
        end
    endtask

    task automatic launch_op(
        input logic operation_mode,
        input logic [N-1:0] response_value,
        input logic [N-1:0] helper_value
    );
        @(negedge clk);
        if (busy) $fatal(1, "Testbench attempted an operation while busy");
        mode = operation_mode;
        response_in = response_value;
        helper_in = helper_value;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
    endtask

    task automatic run_op(
        input logic operation_mode,
        input logic [N-1:0] response_value,
        input logic [N-1:0] helper_value
    );
        int cycles;
        launch_op(operation_mode, response_value, helper_value);
        cycles = 0;
        while (!done && cycles < OP_TIMEOUT) begin
            @(negedge clk);
            cycles++;
        end
        if (!done) $fatal(1, "FE operation timeout: mode=%0d state=%0d op=%0d",
                          operation_mode, dut.state, operations);
        operations++;
        @(negedge clk);
        check("done is a one-cycle pulse", !done);
    endtask

    task automatic check_root(input string name, input logic [K-1:0] expected);
        check({name, ": success"}, success);
        check({name, ": original enrollment root"}, key_out == expected);
        corrected_cases++;
    endtask

    // The external wrapper has reset; exercise restarting while the resetless
    // BCH sub-pipelines may still contain a partly processed transaction.
    task automatic abort_and_recover(input logic [3:0] target_state);
        int cycles;
        launch_op(1'b1, reference_response, reference_helper);
        cycles = 0;
        while (dut.state != target_state && cycles < OP_TIMEOUT) begin
            @(negedge clk);
            cycles++;
        end
        if (dut.state != target_state)
            $fatal(1, "Could not reach reset target state %0d", target_state);
        rst_n = 1'b0;
        repeat (8) @(negedge clk);
        check("reset clears FE busy/done/success/key", !busy && !done &&
              !success && key_out == '0);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        run_op(1'b1, reference_response, reference_helper);
        check_root($sformatf("reconstruct after reset in state %0d", target_state),
                   reference_key);
    endtask

    initial begin
        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        random_response(reference_response);
        reference_key = reference_response[N-1 -: K];
        run_op(1'b0, reference_response, '0);
        reference_helper = helper_out;
        check("enrollment root is the response data portion", key_out == reference_key);
        check("systematic helper has zero data portion", helper_out[N-1 -: K] == '0);

        for (int bit_index = 0; bit_index < N; bit_index++) begin
            error_mask = '0;
            error_mask[bit_index] = 1'b1;
            run_op(1'b1, reference_response ^ error_mask, reference_helper);
            check_root($sformatf("single-bit position %0d", bit_index), reference_key);
        end
        $display("FE_CHARACTERIZATION_SINGLE_BIT cases=%0d failures=%0d", N, failures);

        for (int weight = 0; weight <= 8; weight++) begin
            for (int sample_index = 0; sample_index < SAMPLES_PER_WEIGHT; sample_index++) begin
                random_response(sample_response);
                run_op(1'b0, sample_response, '0);
                sample_helper = helper_out;
                check("random enrollment key", key_out == sample_response[N-1 -: K]);
                make_error_mask(weight, sample_index % 3, error_mask);
                check("injected error weight is exact", $countones(error_mask) == weight);
                run_op(1'b1, sample_response ^ error_mask, sample_helper);
                check_root($sformatf("random weight=%0d sample=%0d", weight, sample_index),
                           sample_response[N-1 -: K]);
            end
            $display("FE_CHARACTERIZATION_WEIGHT weight=%0d cases=%0d failures=%0d",
                     weight, SAMPLES_PER_WEIGHT, failures);
        end

        // Retain the original helper across intervening enrollments and resets.
        abort_and_recover(4'd3); // decode feed
        abort_and_recover(4'd4); // decode wait
        abort_and_recover(4'd7); // verify encode

        // An explicit limitation, not a requirement to reject all >t errors:
        // H0 ^ R0 = C0; H1 ^ R1 = C1; delta=C0^C1 is a nonzero codeword.
        // Reconstructing R0^delta with H0 supplies C1 to the BCH decoder,
        // so success is valid but the enrollment root has changed.
        alternate_response = reference_response;
        alternate_response[PARITY_BITS] = ~alternate_response[PARITY_BITS];
        run_op(1'b0, alternate_response, '0);
        alternate_helper = helper_out;
        codeword_delta = reference_helper ^ reference_response ^
                         alternate_helper ^ alternate_response;
        check("nonzero codeword delta is outside correction radius", $countones(codeword_delta) > 8);
        run_op(1'b1, reference_response ^ codeword_delta, reference_helper);
        check("valid-codeword delta is accepted", success);
        check("accepted delta returns alternate root", key_out == alternate_response[N-1 -: K]);
        check("accepted delta does not return original root", key_out != reference_key);
        $display("FE_EXPECTED_LIMITATION codeword_delta_weight=%0d success=%0d wrong_root=%0d",
                 $countones(codeword_delta), success, key_out != reference_key);

        // A final known-good transaction must still recover the original root.
        run_op(1'b1, reference_response, reference_helper);
        check_root("final clean reconstruction", reference_key);
        $display("FE_CHARACTERIZATION_RESULT checks=%0d corrected_cases=%0d operations=%0d failures=%0d",
                 checks, corrected_cases, operations, failures);
        if (failures != 0) $fatal(1, "FE characterization failed");
        $display("FE_CHARACTERIZATION_PASS");
        $finish;
    end
endmodule
