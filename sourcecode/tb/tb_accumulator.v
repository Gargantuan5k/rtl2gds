// =============================================================================
// Testbench: tb_accumulator
// Tests: basic accumulation, clear, overflow detection, valid gating
// =============================================================================
`timescale 1ns/1ps

module tb_accumulator;

    reg        clk, rst_n, valid_in, clear;
    reg  signed [31:0] data_in;
    wire signed [31:0] acc_out;
    wire               overflow;

    accumulator dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .clear(clear), .data_in(data_in),
        .acc_out(acc_out), .overflow(overflow)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0;

    task check;
        input signed [31:0] exp_acc;
        input               exp_ov;
        begin
            @(posedge clk); #1;
            if (acc_out === exp_acc && overflow === exp_ov) begin
                $display("PASS: acc=%0d overflow=%0b", acc_out, overflow);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL: acc=%0d (exp %0d) overflow=%0b (exp %0b)",
                         acc_out, exp_acc, overflow, exp_ov);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_accumulator.vcd");
        $dumpvars(0, tb_accumulator);

        rst_n = 0; valid_in = 0; clear = 0; data_in = 0;
        repeat(4) @(posedge clk);
        rst_n = 1; @(posedge clk); #1;

        // Basic accumulation: 10 + 20 + 30 = 60
        @(negedge clk); data_in = 32'sd10; valid_in = 1;
        check(32'sd10, 1'b0);
        @(negedge clk); data_in = 32'sd20;
        check(32'sd30, 1'b0);
        @(negedge clk); data_in = 32'sd30;
        check(32'sd60, 1'b0);
        valid_in = 0;

        // Synchronous clear
        @(negedge clk); clear = 1;
        @(posedge clk); #1;
        clear = 0;
        if (acc_out === 32'sd0) begin
            $display("PASS: clear works"); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: clear, acc=%0d", acc_out); fail_cnt = fail_cnt + 1;
        end

        // valid_in=0: should not accumulate
        @(negedge clk); data_in = 32'sd999; valid_in = 0;
        @(posedge clk); #1;
        if (acc_out === 32'sd0) begin
            $display("PASS: valid gate works"); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: valid gate, acc=%0d", acc_out); fail_cnt = fail_cnt + 1;
        end

        // Overflow test: add two large positives
        @(negedge clk); clear = 1;
        @(posedge clk); #1; clear = 0;
        @(negedge clk); data_in = 32'sh7FFF_FFFF; valid_in = 1;
        check(32'sh7FFF_FFFF, 1'b0);
        @(negedge clk); data_in = 32'sd1;
        @(posedge clk); #1;
        if (overflow === 1'b1) begin
            $display("PASS: overflow detected"); pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: overflow not detected"); fail_cnt = fail_cnt + 1;
        end
        valid_in = 0;

        $display("\n=== accumulator: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule
