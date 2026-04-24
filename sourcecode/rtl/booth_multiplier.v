// =============================================================================
// Module: booth_multiplier
// Description: 16-bit Radix-2 Booth Multiplier
//              Produces a 32-bit signed product using Modified Booth encoding.
//              Purely combinational with registered output for pipeline use.
// Inputs:  a, b — 16-bit signed operands (2's complement)
// Outputs: product — 32-bit signed result
// =============================================================================
`timescale 1ns/1ps
module booth_multiplier (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in, // handshake to check if the input that we receive HAS to be processed or not (there may be garbage data in a real system due to various factors)
    input  wire signed [15:0] a,        // multiplicand 
    input  wire signed [15:0] b,        // multiplier
    output reg  signed [31:0] product,
    output reg               valid_out // mirrors valid_in but delayed by one cycle, handshake to verify that the output is correct
);

    integer i;
    reg signed [31:0] partial_sum;
    reg signed [32:0] extended_a;
    reg [17:0] b_ext;

    always @(*) begin
        b_ext        = {b[15], b, 1'b0};
        extended_a   = {{17{a[15]}}, a};
        partial_sum  = 32'sd0;

        for (i = 0; i < 16; i = i + 1) begin
            case (b_ext[i +:2])
                2'b01: partial_sum = partial_sum + (extended_a <<< i);
                2'b10: partial_sum = partial_sum - (extended_a <<< i);
                default: ;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product   <= 32'sd0;
            valid_out <= 1'b0;
        end else begin
            product   <= partial_sum;
            valid_out <= valid_in;
        end
    end

endmodule
