// =============================================================================
// Module: conv_engine
// Description: 3x3 pipelined convolution engine.
//              Accepts one pixel-weight pair per cycle for 9 cycles.
//              Outputs the dot-product (sum of 9 MACs) after the pipeline drains.
//
// Data format: 16-bit signed fixed-point for both pixels and weights.
//              Accumulator output is 32-bit signed.
//
// Protocol:
//   1. Assert start=1 for one cycle to reset the accumulator and begin.
//   2. Present pixel[i] and weight[i] with valid_in=1 for 9 consecutive cycles.
//   3. done goes high when the convolution result is ready on result_out.
//      done remains high for one cycle.
//
// Latency: 9 input cycles + 2 pipeline stages = 11 cycles from first valid_in
//          to done (with start on cycle 0 and first pixel on cycle 1).
// =============================================================================
module conv_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          // pulse: resets accumulator, begins new conv
    input  wire        valid_in,       // one pixel-weight pair presented
    input  wire signed [15:0] pixel,   // input feature map pixel
    input  wire signed [15:0] weight,  // filter weight
    output wire signed [31:0] result_out,
    output wire               done,    // one-cycle pulse when result is valid
    output wire               overflow
);

    // -----------------------------------------------------------------------
    // Input counter: count 9 valid inputs, then stop
    // -----------------------------------------------------------------------
    reg [3:0] input_cnt;   // counts 0..8
    reg       mac_active;  // high while 9 inputs are being fed

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_cnt <= 4'd0;
            mac_active <= 1'b0;
        end else if (start) begin
            input_cnt  <= 4'd0;
            mac_active <= 1'b1;
        end else if (mac_active && valid_in) begin
            if (input_cnt == 4'd8) begin
                input_cnt  <= 4'd0;
                mac_active <= 1'b0;
            end else begin
                input_cnt <= input_cnt + 4'd1;
            end
        end
    end

    wire mac_valid = mac_active && valid_in;

    // -----------------------------------------------------------------------
    // Pipelined MAC (2-stage: multiply then accumulate)
    // clear is issued on start (delayed into MAC to align with pipeline)
    // -----------------------------------------------------------------------
    pipelined_mac u_mac (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (mac_valid),
        .clear     (start),
        .a         (pixel),
        .b         (weight),
        .acc_out   (result_out),
        .valid_out (/* unused — use done below */),
        .overflow  (overflow)
    );

    // -----------------------------------------------------------------------
    // done signal: fires 2 cycles after last mac_valid (pipeline drain)
    // Last mac_valid is the cycle when input_cnt == 8 && valid_in && mac_active
    // -----------------------------------------------------------------------
    wire last_input = mac_active && valid_in && (input_cnt == 4'd8);

    reg last_d1, last_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_d1 <= 1'b0;
            last_d2 <= 1'b0;
        end else begin
            last_d1 <= last_input;
            last_d2 <= last_d1;
        end
    end

    assign done = last_d2;

endmodule
