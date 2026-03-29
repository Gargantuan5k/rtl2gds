// =============================================================================
// Module: pipelined_mac
// Description: 2-stage pipelined Multiply-Accumulate unit.
//   Stage 1: Booth multiplication  (booth_multiplier — registered output)
//   Stage 2: Accumulation          (accumulator)
//
//   Latency : 2 clock cycles from valid_in to first valid acc_out
//   Throughput: 1 MAC/cycle after pipeline is filled
//
// Ports:
//   a, b       — 16-bit signed operands
//   valid_in   — start of a new MAC operation
//   clear      — synchronous clear of accumulator (use between filter outputs)
//   acc_out    — 32-bit accumulated result
//   valid_out  — result valid (2-cycle delayed valid_in)
//   overflow   — accumulator overflow flag
// =============================================================================
module pipelined_mac (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire        clear,
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    output wire signed [31:0] acc_out,
    output wire               valid_out,
    output wire               overflow
);

    // ----- Stage 1: Booth Multiplier -----
    wire signed [31:0] product;
    wire               mult_valid;

    booth_multiplier u_mult (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .a         (a),
        .b         (b),
        .product   (product),
        .valid_out (mult_valid)
    );

    // clear must be delayed by 1 cycle to align with multiplier output
    reg clear_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clear_d1 <= 1'b0;
        else        clear_d1 <= clear;
    end

    // ----- Stage 2: Accumulator -----
    accumulator u_acc (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid_in (mult_valid),
        .clear    (clear_d1),
        .data_in  (product),
        .acc_out  (acc_out),
        .overflow (overflow)
    );

    // valid_out: 2-cycle delay of original valid_in
    reg valid_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_d1 <= 1'b0;
        else        valid_d1 <= mult_valid;
    end
    assign valid_out = valid_d1;

endmodule
