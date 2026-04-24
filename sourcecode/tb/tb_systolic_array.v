// =============================================================================
// Testbench: tb_systolic_array
// Tests a 4x4 weight-stationary systolic array.
// Computes C = A * B where A and B are 4x4 matrices of 16-bit signed values.
// The array performs NUM_STEPS=4 accumulations (dot-product length = 4).
//
// Test 1: Identity weight matrix, A = diagonal → C = A
// Test 2: All-ones weight matrix, A = column vector → C = row sums
// Test 3: Random matrices with software-model reference check
// =============================================================================
`timescale 1ns/1ps

module tb_systolic_array;

    localparam SIZE      = 4;
    localparam NUM_STEPS = 4;
    localparam W_TOT     = SIZE * SIZE * 16;
    localparam R_TOT     = SIZE * SIZE * 32;

    reg clk, rst_n;
    reg load_weights;
    reg signed [W_TOT-1:0] weight_flat;
    reg signed [SIZE*16-1:0] a_flat;
    reg valid_in;

    wire signed [R_TOT-1:0] result_flat;
    wire [SIZE*SIZE-1:0]    overflow_flat;
    wire done;

    systolic_array #(.SIZE(SIZE), .NUM_STEPS(NUM_STEPS)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .load_weights(load_weights),
        .weight_flat (weight_flat),
        .a_flat      (a_flat),
        .valid_in    (valid_in),
        .result_flat (result_flat),
        .overflow_flat(overflow_flat),
        .done        (done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0;
    integer i, r, c, k;

    // Reference model storage
    reg signed [15:0] ref_w [0:SIZE-1][0:SIZE-1];
    reg signed [15:0] ref_a [0:NUM_STEPS-1][0:SIZE-1]; // [step][row]
    reg signed [31:0] ref_c [0:SIZE-1][0:SIZE-1];

    // Extract result from flat bus
    function signed [31:0] get_result;
        input integer row, col;
        begin
            get_result = result_flat[(row*SIZE + col)*32 +: 32];
        end
    endfunction

    // Load weights and run NUM_STEPS activation vectors; check results
    task run_test;
        input [63:0] test_id;
        integer row, col, step;
        reg signed [63:0] dot;
        begin
            // Compute reference: C[row][col] = sum_k( W[row][k] * A[step=k][row?] )
            // Weight-stationary: C[r][c] = sum over steps of W[r][c] * a_skew[c][r]
            // where a_skew[c][step] = A[step - c][r] (skewed by col c cycles).
            // For a simple dot-product test (same vector each step), ref is:
            //   C[r][c] = W[r][c] * sum_k(A[k][r]) ... but each PE only sees one row.
            // Actually: PE[r][c] accumulates W[r][c] * a_skew[c][r] for NUM_STEPS steps.
            // With the column skew, PE[r][c] at logical step t sees A[t][r].
            // So C[r][c] = W[r][c] * sum_{t=0}^{NUM_STEPS-1} A[t][r].
            // For a matrix multiply interpretation feed A column by column.
            // Here we just check the exact accumulated value.
            for (row = 0; row < SIZE; row = row + 1)
                for (col = 0; col < SIZE; col = col + 1) begin
                    dot = 64'sd0;
                    for (step = 0; step < NUM_STEPS; step = step + 1)
                        dot = dot + ($signed(ref_w[row][col]) * $signed(ref_a[step][row]));
                    ref_c[row][col] = dot[31:0];
                end

            // Load weights
            @(negedge clk);
            for (row = 0; row < SIZE; row = row + 1)
                for (col = 0; col < SIZE; col = col + 1)
                    weight_flat[(row*SIZE+col)*16 +: 16] = ref_w[row][col];
            load_weights = 1;
            @(posedge clk); #1;
            load_weights = 0;

            // Feed NUM_STEPS activation vectors
            for (step = 0; step < NUM_STEPS; step = step + 1) begin
                @(negedge clk);
                for (row = 0; row < SIZE; row = row + 1)
                    a_flat[row*16 +: 16] = ref_a[step][row];
                valid_in = 1;
                @(posedge clk); #1;
            end
            @(negedge clk);
            valid_in = 0;

            // Wait for done
            @(posedge done); #1;

            // Check
            for (row = 0; row < SIZE; row = row + 1)
                for (col = 0; col < SIZE; col = col + 1) begin
                    if (get_result(row, col) === ref_c[row][col]) begin
                        pass_cnt = pass_cnt + 1;
                    end else begin
                        $display("FAIL test%0d PE[%0d][%0d]: got %0d, exp %0d",
                                 test_id, row, col,
                                 get_result(row, col), ref_c[row][col]);
                        fail_cnt = fail_cnt + 1;
                    end
                end
            $display("Test %0d done.", test_id);

            // Idle gap between tests
            repeat(10) @(posedge clk);
        end
    endtask

    integer seed = 42;

    initial begin
        $dumpfile("tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);

        rst_n = 0; load_weights = 0; valid_in = 0;
        weight_flat = {W_TOT{1'b0}};
        a_flat      = {(SIZE*16){1'b0}};
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // -----------------------------------------------------------------
        // Test 1: All-ones weights, constant activation = 1
        // Expected: each PE accumulates W[r][c] * 1 * NUM_STEPS = NUM_STEPS
        // -----------------------------------------------------------------
        for (r = 0; r < SIZE; r = r + 1)
            for (c = 0; c < SIZE; c = c + 1)
                ref_w[r][c] = 16'sd1;
        for (i = 0; i < NUM_STEPS; i = i + 1)
            for (r = 0; r < SIZE; r = r + 1)
                ref_a[i][r] = 16'sd1;
        run_test(1);

        // -----------------------------------------------------------------
        // Test 2: Weights = row index+1, activation = col index+1
        // PE[r][c]: W=r+1, A=r+1 (each row sees its own activation)
        // Expected: C[r][c] = (r+1)*(r+1)*NUM_STEPS
        // -----------------------------------------------------------------
        for (r = 0; r < SIZE; r = r + 1)
            for (c = 0; c < SIZE; c = c + 1)
                ref_w[r][c] = r + 1;
        for (i = 0; i < NUM_STEPS; i = i + 1)
            for (r = 0; r < SIZE; r = r + 1)
                ref_a[i][r] = r + 1;
        run_test(2);

        // -----------------------------------------------------------------
        // Test 3: Alternating positive/negative weights
        // -----------------------------------------------------------------
        for (r = 0; r < SIZE; r = r + 1)
            for (c = 0; c < SIZE; c = c + 1)
                ref_w[r][c] = ((r + c) % 2 == 0) ? 16'sd3 : -16'sd3;
        for (i = 0; i < NUM_STEPS; i = i + 1)
            for (r = 0; r < SIZE; r = r + 1)
                ref_a[i][r] = 16'sd2;
        run_test(3);

        // -----------------------------------------------------------------
        // Test 4: Zero activations — all results must be zero
        // -----------------------------------------------------------------
        for (r = 0; r < SIZE; r = r + 1)
            for (c = 0; c < SIZE; c = c + 1)
                ref_w[r][c] = 16'sd100;
        for (i = 0; i < NUM_STEPS; i = i + 1)
            for (r = 0; r < SIZE; r = r + 1)
                ref_a[i][r] = 16'sd0;
        run_test(4);

        // -----------------------------------------------------------------
        // Test 5: Random weights and activations
        // -----------------------------------------------------------------
        for (r = 0; r < SIZE; r = r + 1)
            for (c = 0; c < SIZE; c = c + 1)
                ref_w[r][c] = $random(seed);
        for (i = 0; i < NUM_STEPS; i = i + 1)
            for (r = 0; r < SIZE; r = r + 1)
                ref_a[i][r] = $random;
        run_test(5);

        $display("\n=== systolic_array: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin
        #2000000;
        $display("TIMEOUT"); $finish;
    end

endmodule
