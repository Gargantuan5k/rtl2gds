// =============================================================================
// Module: systolic_array
// Description: NxN weight-stationary systolic array built from booth_multiplier PEs.
//
//   Architecture:
//     - SIZE x SIZE grid of processing elements (PEs).
//     - Each PE holds one preloaded 16-bit weight.
//     - Activation vectors (SIZE elements, 16-bit signed) are fed one per cycle.
//     - Each column j receives activations skewed by j cycles so all PEs in a
//       column see the same activation at the same logical time step.
//     - Each PE multiplies its weight by the incoming activation and accumulates
//       over NUM_STEPS cycles; booth_multiplier adds one cycle of latency inside
//       each PE, so the accumulator is driven by the registered product.
//     - After NUM_STEPS accumulations the result matrix is valid on result_out
//       and done is asserted for one cycle.
//
//   Protocol:
//     1. Drive weight_flat and pulse load_weights for one cycle.
//     2. Drive a_flat (SIZE activations) with valid_in=1 for NUM_STEPS cycles.
//        Internally the array inserts the column skew; present the same vector
//        each cycle for a straightforward dot-product, or a new one each cycle
//        for a full matrix multiply.
//     3. done pulses one cycle after the pipeline drains; result_flat is valid.
//
//   Latency: NUM_STEPS + SIZE-1 (skew fill) + 2 (booth + acc pipeline) cycles
//            from the first valid_in to done.
//
//   Parameterization:
//     SIZE      — array dimension (default 4 → 4×4 = 16 PEs)
//     NUM_STEPS — accumulation depth (dot-product length, default 16)
// =============================================================================
`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// PE: single processing element
//   Holds one weight; multiplies weight × a_in each valid cycle via
//   booth_multiplier (registered, 1-cycle latency), then accumulates.
//   a_out is a_in registered by one cycle so the next PE in the row sees
//   the activation one cycle later (systolic propagation).
// ---------------------------------------------------------------------------
module systolic_pe (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load_w,           // pulse: latch weight_in
    input  wire signed [15:0] weight_in, // weight to preload
    input  wire signed [15:0] a_in,      // activation flowing in from left
    input  wire        valid_in,         // a_in is valid this cycle
    input  wire        clear,            // synchronous clear of accumulator
    output reg  signed [15:0] a_out,     // a_in registered (flows right)
    output wire signed [31:0] acc_out,   // accumulated partial sum
    output wire               overflow
);

    reg signed [15:0] w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      w <= 16'sd0;
        else if (load_w) w <= weight_in;
    end

    // Propagate activation to next PE (one-cycle skew)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) a_out <= 16'sd0;
        else        a_out <= a_in;
    end

    // Booth multiplier: 1-cycle registered output
    wire signed [31:0] product;
    wire               product_valid;

    booth_multiplier u_mult (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid_in (valid_in),
        .a        (w),
        .b        (a_in),
        .product  (product),
        .valid_out(product_valid)
    );

    // Accumulator: receives registered product from booth_multiplier
    // clear must be delayed 1 cycle to align with the registered product
    reg clear_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clear_d1 <= 1'b0;
        else        clear_d1 <= clear;
    end

    accumulator u_acc (
        .clk     (clk),
        .rst_n   (rst_n),
        .valid_in(product_valid),
        .clear   (clear_d1),
        .data_in (product),
        .acc_out (acc_out),
        .overflow(overflow)
    );

endmodule


// ---------------------------------------------------------------------------
// systolic_array: SIZE x SIZE grid of systolic_pe instances
// ---------------------------------------------------------------------------
module systolic_array #(
    parameter SIZE      = 4,   // array dimension
    parameter NUM_STEPS = 16   // accumulation depth (dot-product length)
) (
    input  wire clk,
    input  wire rst_n,

    // Weight loading (preload before computation)
    input  wire load_weights,                              // one-cycle pulse
    input  wire signed [SIZE*SIZE*16-1:0] weight_flat,    // row-major: w[row][col]

    // Activation input: SIZE 16-bit values per cycle, driven for NUM_STEPS cycles
    input  wire signed [SIZE*16-1:0] a_flat,
    input  wire valid_in,

    // Output
    output wire signed [SIZE*SIZE*32-1:0] result_flat,    // row-major: acc[row][col]
    output wire [SIZE*SIZE-1:0]           overflow_flat,
    output wire done
);

    // -----------------------------------------------------------------------
    // Column skew: column j sees a_flat delayed by j cycles.
    // Skew registers: skew[j][row] — SIZE columns, each SIZE-wide vector.
    // skew_valid[j] tracks when the skewed column is valid.
    // -----------------------------------------------------------------------
    // a_skew[j] = a_flat delayed j cycles
    // We need SIZE delay stages; skew[0] = a_flat (no delay).
    reg signed [SIZE*16-1:0] a_skew [0:SIZE-1];
    reg                      v_skew [0:SIZE-1];

    integer sk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (sk = 0; sk < SIZE; sk = sk + 1) begin
                a_skew[sk] <= {(SIZE*16){1'b0}};
                v_skew[sk] <= 1'b0;
            end
        end else begin
            // Column 0: direct
            a_skew[0] <= a_flat;
            v_skew[0] <= valid_in;
            // Column j: delayed from column j-1
            for (sk = 1; sk < SIZE; sk = sk + 1) begin
                a_skew[sk] <= a_skew[sk-1];
                v_skew[sk] <= v_skew[sk-1];
            end
        end
    end

    // -----------------------------------------------------------------------
    // Step counter and clear/done generation
    // -----------------------------------------------------------------------
    localparam CTR_W = $clog2(NUM_STEPS + SIZE + 4);

    reg [CTR_W-1:0] step_cnt;
    reg             running;

    // Clear accumulator when valid_in first arrives (start of new computation)
    // We pulse clear on the cycle valid_in rises from 0->1
    reg valid_in_prev;
    wire clear_pulse = valid_in && !valid_in_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_in_prev <= 1'b0;
            step_cnt      <= {CTR_W{1'b0}};
            running       <= 1'b0;
        end else begin
            valid_in_prev <= valid_in;
            if (clear_pulse) begin
                // Count the clear beat as step 1 so last_col0 fires on
                // the NUM_STEPS-th valid beat, not one beat too late.
                step_cnt <= {{(CTR_W-1){1'b0}}, 1'b1};
                running  <= 1'b1;
            end else if (running && valid_in) begin
                if (step_cnt == NUM_STEPS - 1) begin
                    step_cnt <= {CTR_W{1'b0}};
                    running  <= 1'b0;
                end else begin
                    step_cnt <= step_cnt + 1'b1;
                end
            end
        end
    end

    // last_input: final valid beat entering column 0
    wire last_col0 = running && valid_in && (step_cnt == NUM_STEPS - 1);

    // done fires after: last_col0 + (SIZE-1) skew cycles + 2 pipeline cycles
    // Total delay from last_col0 = SIZE+1 cycles (SIZE-1 skew + 2 booth+acc).
    localparam DRAIN = SIZE + 2;  // cycles from last_col0 to done
    // last_col0 → v_skew[SIZE-1] last high: SIZE cycles later
    // → booth product_valid last high: 1 more cycle
    // → accumulator captures: 1 more cycle (total SIZE+2)

    reg [DRAIN-1:0] drain_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) drain_sr <= {DRAIN{1'b0}};
        else        drain_sr <= {drain_sr[DRAIN-2:0], last_col0};
    end
    assign done = drain_sr[DRAIN-1];

    // -----------------------------------------------------------------------
    // PE grid instantiation
    // Wire: pe_a[row][col] — activation bus between PE columns
    // pe_a[row][0] = a_skew[0][row*16+:16] = a_flat[row], no skew on col 0
    //   but column skew is already handled by a_skew above:
    //   column j reads from a_skew[j], so pe_a[row][0] = a_skew[0][row*16+:16]
    // Within a column, activations don't propagate row-to-row (weight-stationary).
    // Each PE in column j takes its activation from a_skew[j].
    // a_out of each PE is unused (no horizontal propagation needed in
    // weight-stationary mode; the skew registers handle the delay externally).
    // -----------------------------------------------------------------------
    genvar row, col;
    generate
        for (row = 0; row < SIZE; row = row + 1) begin : gen_row
            for (col = 0; col < SIZE; col = col + 1) begin : gen_col

                wire signed [15:0] w_in;
                wire signed [15:0] a_unused_out;
                wire signed [31:0] acc;
                wire               ov;

                // Weight: row-major index = row*SIZE + col
                assign w_in = weight_flat[(row*SIZE + col)*16 +: 16];

                systolic_pe u_pe (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .load_w    (load_weights),
                    .weight_in (w_in),
                    .a_in      (a_skew[col][row*16 +: 16]),
                    .valid_in  (v_skew[col]),
                    .clear     (clear_pulse),
                    .a_out     (a_unused_out),
                    .acc_out   (acc),
                    .overflow  (ov)
                );

                assign result_flat  [(row*SIZE + col)*32 +: 32] = acc;
                assign overflow_flat[(row*SIZE + col)]          = ov;
            end
        end
    endgenerate

endmodule
