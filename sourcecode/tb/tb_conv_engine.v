// =============================================================================
// Testbench: tb_conv_engine
// Tests: 3x3 convolution correctness, done pulse, back-to-back convolutions
//
// Reference: C-model computed in $display expected values
// =============================================================================
`timescale 1ns/1ps

module tb_conv_engine;

    reg        clk, rst_n, start, valid_in;
    reg  signed [15:0] pixel, weight;
    wire signed [31:0] result_out;
    wire               done, overflow;

    conv_engine dut (
        .clk(clk), .rst_n(rst_n), .start(start), .valid_in(valid_in),
        .pixel(pixel), .weight(weight),
        .result_out(result_out), .done(done), .overflow(overflow)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0;

    // Compute expected dot product in simulation
    function signed [31:0] ref_conv;
        input signed [15:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;
        input signed [15:0] w0, w1, w2, w3, w4, w5, w6, w7, w8;
        begin
            ref_conv = p0*w0 + p1*w1 + p2*w2 +
                       p3*w3 + p4*w4 + p5*w5 +
                       p6*w6 + p7*w7 + p8*w8;
        end
    endfunction

    // Arrays for a test case
    reg signed [15:0] pixels [0:8];
    reg signed [15:0] weights[0:8];
    integer i;

    task run_conv;
        input signed [31:0] expected;
        integer j;
        begin
            // Issue start pulse
            @(negedge clk); start = 1;
            @(posedge clk); #1; start = 0;

            // Feed 9 pixel-weight pairs
            for (j = 0; j < 9; j = j + 1) begin
                @(negedge clk);
                pixel  = pixels[j];
                weight = weights[j];
                valid_in = 1;
                @(posedge clk); #1;
            end
            valid_in = 0;

            // Wait for done
            @(posedge done); #1;

            if (result_out === expected) begin
                $display("PASS: conv result=%0d", result_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL: conv result=%0d (expected %0d)", result_out, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_conv_engine.vcd");
        $dumpvars(0, tb_conv_engine);

        rst_n = 0; start = 0; valid_in = 0; pixel = 0; weight = 0;
        repeat(4) @(posedge clk); rst_n = 1; @(posedge clk);

        // ----------------------------------------------------------------
        // Test 1: All ones — 9 * 1*1 = 9
        // ----------------------------------------------------------------
        for (i = 0; i < 9; i = i + 1) begin pixels[i] = 16'sd1; weights[i] = 16'sd1; end
        run_conv(32'sd9);

        // ----------------------------------------------------------------
        // Test 2: pixels = 1..9, weights = 1..9, sum of squares = 285
        // ----------------------------------------------------------------
        for (i = 0; i < 9; i = i + 1) begin
            pixels[i]  = i + 1;
            weights[i] = i + 1;
        end
        run_conv(32'sd285);

        // ----------------------------------------------------------------
        // Test 3: Sobel-like horizontal edge kernel [-1,-2,-1, 0,0,0, 1,2,1]
        //         applied to flat patch [1,1,1, 1,1,1, 1,1,1] → 0
        // ----------------------------------------------------------------
        pixels[0]=1; pixels[1]=1; pixels[2]=1;
        pixels[3]=1; pixels[4]=1; pixels[5]=1;
        pixels[6]=1; pixels[7]=1; pixels[8]=1;
        weights[0]=-1; weights[1]=-2; weights[2]=-1;
        weights[3]=0;  weights[4]=0;  weights[5]=0;
        weights[6]=1;  weights[7]=2;  weights[8]=1;
        run_conv(32'sd0);

        // ----------------------------------------------------------------
        // Test 4: Edge detection on a vertical step edge
        //         pixels: left half=0, right half=255
        //         patch: [0,0,255, 0,0,255, 0,0,255]
        //         Sobel-vertical kernel [-1,0,1, -2,0,2, -1,0,1]
        //         expected = 0*-1+0*0+255*1 + 0*-2+0*0+255*2 + 0*-1+0*0+255*1
        //                  = 255 + 510 + 255 = 1020
        // ----------------------------------------------------------------
        pixels[0]=0;   pixels[1]=0;   pixels[2]=16'sd255;
        pixels[3]=0;   pixels[4]=0;   pixels[5]=16'sd255;
        pixels[6]=0;   pixels[7]=0;   pixels[8]=16'sd255;
        weights[0]=-1; weights[1]=0;  weights[2]=1;
        weights[3]=-2; weights[4]=0;  weights[5]=2;
        weights[6]=-1; weights[7]=0;  weights[8]=1;
        run_conv(32'sd1020);

        // ----------------------------------------------------------------
        // Test 5: Back-to-back convolutions (no idle gap)
        // ----------------------------------------------------------------
        for (i = 0; i < 9; i = i + 1) begin pixels[i] = 16'sd2; weights[i] = 16'sd3; end
        // 9 * 2*3 = 54
        run_conv(32'sd54);
        // immediately again
        for (i = 0; i < 9; i = i + 1) begin pixels[i] = -16'sd5; weights[i] = 16'sd4; end
        // 9 * -5*4 = -180
        run_conv(-32'sd180);

        // ----------------------------------------------------------------
        // Test 6: Mixed-sign weights (identity-like center kernel)
        //         kernel: [0,0,0, 0,1,0, 0,0,0] → passes center pixel
        //         center pixel = 42
        // ----------------------------------------------------------------
        for (i = 0; i < 9; i = i + 1) begin pixels[i] = 16'sd0; weights[i] = 16'sd0; end
        pixels[4] = 16'sd42;
        weights[4] = 16'sd1;
        run_conv(32'sd42);

        $display("\n=== conv_engine: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule
