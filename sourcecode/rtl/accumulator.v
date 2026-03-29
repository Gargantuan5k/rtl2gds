// =============================================================================
// Module: accumulator
// Description: 32-bit signed accumulator with synchronous clear.
//              Accumulates valid_in-gated data; clear resets sum to 0.
// Inputs:  data_in   — 32-bit signed value to add
//          valid_in  — gate: only accumulate when high
//          clear     — synchronous reset of accumulator register
// Outputs: acc_out   — running sum (32-bit signed)
//          overflow  — sticky flag set when saturation/wrap detected
// =============================================================================
module accumulator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire        clear,
    input  wire signed [31:0] data_in,
    output reg  signed [31:0] acc_out,
    output reg               overflow
);

    reg signed [32:0] full_sum;   // 33-bit to capture carry/overflow

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out  <= 32'sd0;
            overflow <= 1'b0;
        end else if (clear) begin
            acc_out  <= 32'sd0;
            overflow <= 1'b0;
        end else if (valid_in) begin
            full_sum = {acc_out[31], acc_out} + {data_in[31], data_in};
            // Overflow: sign bits of both operands same but result sign differs
            overflow <= (acc_out[31] == data_in[31]) && (full_sum[31] != acc_out[31]);
            acc_out  <= full_sum[31:0];
        end
    end

endmodule
