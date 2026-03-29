// =============================================================================
// Testbench: tb_booth_multiplier
// =============================================================================
`timescale 1ns/1ps

module tb_booth_multiplier;

    reg        clk, rst_n, valid_in;
    reg  signed [15:0] a, b;
    wire signed [31:0] product;
    wire               valid_out;

    booth_multiplier dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .a(a), .b(b), .product(product), .valid_out(valid_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0;

    // Apply inputs, wait one clock, read registered output
    task apply_and_check;
        input signed [15:0] ta, tb_in;
        input signed [31:0] expected;
        begin
            @(negedge clk);
            a = ta; b = tb_in; valid_in = 1;
            @(posedge clk); #1;   // product and valid_out registered here
            valid_in = 0;
            if (product === expected) begin
                $display("PASS: %0d * %0d = %0d", ta, tb_in, product);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL: %0d * %0d = %0d (expected %0d)", ta, tb_in, product, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    integer i;
    reg signed [31:0] exp_rand;

    initial begin
        $dumpfile("tb_booth_multiplier.vcd");
        $dumpvars(0, tb_booth_multiplier);

        rst_n = 0; valid_in = 0; a = 0; b = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        apply_and_check(16'sd3,      16'sd5,      32'sd15);
        apply_and_check(16'sd100,    16'sd200,    32'sd20000);
        apply_and_check(-16'sd3,     16'sd5,      -32'sd15);
        apply_and_check(-16'sd7,     -16'sd7,     32'sd49);
        apply_and_check(16'sd0,      16'sd12345,  32'sd0);
        apply_and_check(16'sd1,      16'sd1,      32'sd1);
        apply_and_check(-16'sd1,     16'sd1,      -32'sd1);
        apply_and_check(16'sd32767,  16'sd32767,  32'sd1073676289);
        apply_and_check(-16'sd32768, 16'sd1,      -32'sd32768);
        apply_and_check(-16'sd32768, -16'sd32768, 32'sd1073741824);

        // Random tests
        for (i = 0; i < 20; i = i + 1) begin
            @(negedge clk);
            a = $random; b = $random;
            exp_rand = $signed(a) * $signed(b);
            valid_in = 1;
            @(posedge clk); #1;
            valid_in = 0;
            if (product === exp_rand) begin
                $display("PASS(rand): %0d * %0d = %0d", $signed(a), $signed(b), product);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL(rand): %0d * %0d = %0d (exp %0d)",
                         $signed(a), $signed(b), product, exp_rand);
                fail_cnt = fail_cnt + 1;
            end
        end

        $display("\n=== booth_multiplier: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT"); $finish;
    end

endmodule
