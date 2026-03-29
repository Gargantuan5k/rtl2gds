// =============================================================================
// Testbench: tb_pipelined_mac
// Tests: dot-product correctness, pipeline latency, back-to-back ops, clear
// =============================================================================
`timescale 1ns/1ps

module tb_pipelined_mac;

    reg        clk, rst_n, valid_in, clear;
    reg  signed [15:0] a, b;
    wire signed [31:0] acc_out;
    wire               valid_out, overflow;

    pipelined_mac dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .clear(clear),
        .a(a), .b(b), .acc_out(acc_out), .valid_out(valid_out), .overflow(overflow)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0;
    integer k;

    // Feed N mac operations: arrays a_arr, b_arr of length n
    // then wait for valid_out and check against expected
    task run_mac_sequence;
        input integer n;
        input signed [31:0] expected;
        reg signed [31:0] ref_sum;
        integer j;
        begin
            ref_sum = 0;
            // clear first
            @(negedge clk); clear = 1;
            @(posedge clk); #1; clear = 0;

            for (j = 0; j < n; j = j + 1) begin
                // a, b set externally before calling — use internal regs
                @(negedge clk); valid_in = 1;
                @(posedge clk); #1;
            end
            valid_in = 0;
            // drain pipeline (2 stages)
            repeat(3) @(posedge clk);
            #1;
            if (acc_out === expected) begin
                $display("PASS: acc=%0d", acc_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL: acc=%0d (exp %0d)", acc_out, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_pipelined_mac.vcd");
        $dumpvars(0, tb_pipelined_mac);

        rst_n = 0; valid_in = 0; clear = 0; a = 0; b = 0;
        repeat(4) @(posedge clk); rst_n = 1;

        // Test 1: single MAC 3*5=15
        @(negedge clk); clear = 1;
        @(posedge clk); #1; clear = 0;
        a = 16'sd3; b = 16'sd5;
        @(negedge clk); valid_in = 1;
        @(posedge clk); #1; valid_in = 0;
        repeat(4) @(posedge clk); #1;
        if (acc_out === 32'sd15) begin
            $display("PASS: 3*5=%0d", acc_out); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: 3*5, got %0d", acc_out); fail_cnt = fail_cnt + 1;
        end

        // Test 2: dot product [1,2,3]·[4,5,6] = 4+10+18 = 32
        @(negedge clk); clear = 1;
        @(posedge clk); #1; clear = 0;

        @(negedge clk); a = 16'sd1; b = 16'sd4; valid_in = 1;
        @(posedge clk); #1;
        @(negedge clk); a = 16'sd2; b = 16'sd5;
        @(posedge clk); #1;
        @(negedge clk); a = 16'sd3; b = 16'sd6;
        @(posedge clk); #1;
        valid_in = 0;
        repeat(4) @(posedge clk); #1;
        if (acc_out === 32'sd32) begin
            $display("PASS: dot[1,2,3]·[4,5,6]=%0d", acc_out); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: dot product, got %0d", acc_out); fail_cnt = fail_cnt + 1;
        end

        // Test 3: 9-element dot product (3x3 conv kernel)
        // pixels=1..9, weights=1..9, sum = 1+4+9+16+25+36+49+64+81 = 285
        @(negedge clk); clear = 1;
        @(posedge clk); #1; clear = 0;
        begin : blk
            integer p;
            for (p = 1; p <= 9; p = p + 1) begin
                @(negedge clk);
                a = p[15:0]; b = p[15:0]; valid_in = 1;
                @(posedge clk); #1;
            end
        end
        valid_in = 0;
        repeat(4) @(posedge clk); #1;
        if (acc_out === 32'sd285) begin
            $display("PASS: 9-elem sum of squares=%0d", acc_out); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: 9-elem, got %0d", acc_out); fail_cnt = fail_cnt + 1;
        end

        // Test 4: negative values [-1,-2]·[3,4] = -3-8 = -11
        @(negedge clk); clear = 1;
        @(posedge clk); #1; clear = 0;
        @(negedge clk); a = -16'sd1; b = 16'sd3; valid_in = 1;
        @(posedge clk); #1;
        @(negedge clk); a = -16'sd2; b = 16'sd4;
        @(posedge clk); #1;
        valid_in = 0;
        repeat(4) @(posedge clk); #1;
        if (acc_out === -32'sd11) begin
            $display("PASS: neg dot=-11, got %0d", acc_out); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: neg dot, got %0d", acc_out); fail_cnt = fail_cnt + 1;
        end

        $display("\n=== pipelined_mac: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end

endmodule
