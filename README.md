# CNN MAC Accelerator — Phase 1 RTL Documentation

**Project:** ASIC Implementation of a Pipelined Energy-Efficient CNN MAC Accelerator
**Phase:** 1 — RTL Design & Functional Verification
**Data format:** 16-bit signed fixed-point (2's complement)

---

## Directory Structure

```
rtl2gds/
├── docs/
│   ├── CNN MAC Accelerator RTL to GDS-II & ASIC.pdf
│   └── README.md                  ← this file
└── sourcecode/
    ├── rtl/
    │   ├── booth_multiplier.v     ← 16-bit Radix-2 Booth multiplier
    │   ├── accumulator.v          ← 32-bit signed accumulator
    │   ├── pipelined_mac.v        ← 2-stage pipelined MAC
    │   └── conv_engine.v          ← 3×3 convolution engine
    └── tb/
        ├── tb_booth_multiplier.v
        ├── tb_accumulator.v
        ├── tb_pipelined_mac.v
        └── tb_conv_engine.v
```

---

## Module Descriptions

### 1. `booth_multiplier.v`

**Function:** Computes a 16-bit × 16-bit → 32-bit signed product using Radix-2 Booth encoding.

**Algorithm — Radix-2 Booth:**
Examine consecutive bit-pairs `{b[i], b[i-1]}` of the multiplier:
- `01` → add multiplicand shifted left by i
- `10` → subtract multiplicand shifted left by i
- `00` / `11` → no operation

This reduces the average number of partial products compared to a simple array multiplier.

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | Clock |
| `rst_n` | in | 1 | Active-low async reset |
| `valid_in` | in | 1 | Input data valid |
| `a` | in | 16 | Multiplicand (signed) |
| `b` | in | 16 | Multiplier (signed) |
| `product` | out | 32 | Signed product (registered) |
| `valid_out` | out | 1 | Output valid (1-cycle latency) |

**Latency:** 1 clock cycle.

---

### 2. `accumulator.v`

**Function:** 32-bit signed accumulator with synchronous clear and overflow detection.

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | Clock |
| `rst_n` | in | 1 | Active-low async reset |
| `valid_in` | in | 1 | Accumulate when high |
| `clear` | in | 1 | Synchronous reset to 0 |
| `data_in` | in | 32 | Value to add (signed) |
| `acc_out` | out | 32 | Running sum (registered) |
| `overflow` | out | 1 | Sticky overflow flag |

**Overflow detection:** Two same-sign operands producing an opposite-sign result.

---

### 3. `pipelined_mac.v`

**Function:** 2-stage pipelined Multiply-Accumulate unit. Instantiates `booth_multiplier` and `accumulator`.

```
Cycle N:    [Multiply]  a×b → product_reg
Cycle N+1:  [Accumulate] acc += product_reg
```

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | Clock |
| `rst_n` | in | 1 | Active-low async reset |
| `valid_in` | in | 1 | New operand pair ready |
| `clear` | in | 1 | Clear accumulator (aligned to pipeline) |
| `a`, `b` | in | 16 | Signed operands |
| `acc_out` | out | 32 | Accumulated result |
| `valid_out` | out | 1 | Result valid (2-cycle latency) |
| `overflow` | out | 1 | Accumulator overflow |

**Throughput:** 1 MAC/cycle (after 2-cycle fill latency).
**Clear alignment:** `clear` is delayed by 1 cycle internally to align with the pipeline output.

---

### 4. `conv_engine.v`

**Function:** 3×3 spatial convolution over a single channel. Computes the inner product of a 9-element patch with a 9-element filter kernel using the pipelined MAC.

**Protocol:**

```
Cycle 0:     start=1        → resets accumulator, arms input FSM
Cycles 1–9:  valid_in=1     → present pixel[i] and weight[i] each cycle
Cycle 11:    done=1         → result_out holds the convolution output
```

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | Clock |
| `rst_n` | in | 1 | Active-low async reset |
| `start` | in | 1 | One-cycle pulse to begin new convolution |
| `valid_in` | in | 1 | Pixel-weight pair presented this cycle |
| `pixel` | in | 16 | Input feature map value (signed fixed-point) |
| `weight` | in | 16 | Filter coefficient (signed fixed-point) |
| `result_out` | out | 32 | Convolution dot-product result |
| `done` | out | 1 | One-cycle pulse when result is valid |
| `overflow` | out | 1 | Accumulator overflow flag |

**Timing diagram:**
```
clk:       __|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
start:     _|‾|___________________________________________
valid_in:  ______|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|____________________
           (9 pixels fed)
done:      ___________________________________________|‾|__
           (2 cycles after last valid = pipeline drain)
```

**Latency:** 9 input cycles + 2 pipeline stages = 11 cycles total.

---

## Pipeline Architecture

```
                    ┌─────────────────────────────────────────┐
                    │            pipelined_mac                 │
                    │                                          │
  pixel  ──────────►│  ┌──────────────┐    ┌──────────────┐  │
  weight ──────────►│  │   Booth      │    │ Accumulator  │  │──► acc_out
                    │  │  Multiplier  │───►│  (32-bit)    │  │
  valid_in ─────────►│  │  (Stage 1)  │    │  (Stage 2)   │  │──► valid_out
                    │  └──────────────┘    └──────────────┘  │
  clear ────────────►│         │ clear_d1 ────────────────────►│
                    └─────────────────────────────────────────┘
                                     ▲
                    ┌────────────────┴────────────────────────┐
                    │             conv_engine                  │
                    │  Input FSM (counts 9 pairs)              │
                    │  Instantiates pipelined_mac              │
                    │  done = last_input delayed 2 cycles      │
                    └─────────────────────────────────────────┘
```

---

## Running Simulations

### Using Xcelium (Cadence)

```bash
# Compile and simulate booth_multiplier
xrun sourcecode/rtl/booth_multiplier.v sourcecode/tb/tb_booth_multiplier.v -timescale 1ns/1ps -top tb_booth_multiplier -access +r

# Compile and simulate accumulator
xrun sourcecode/rtl/accumulator.v sourcecode/tb/tb_accumulator.v -timescale 1ns/1ps -top tb_accumulator -access +r

# Compile and simulate pipelined_mac (needs all RTL)
xrun sourcecode/rtl/booth_multiplier.v sourcecode/rtl/accumulator.v sourcecode/rtl/pipelined_mac.v sourcecode/tb/tb_pipelined_mac.v -timescale 1ns/1ps -top tb_pipelined_mac -access +r

# Compile and simulate conv_engine (full hierarchy)
xrun sourcecode/rtl/booth_multiplier.v sourcecode/rtl/accumulator.v sourcecode/rtl/pipelined_mac.v sourcecode/rtl/conv_engine.v sourcecode/tb/tb_conv_engine.v -timescale 1ns/1ps -top tb_conv_engine -access +r
```

### Using Icarus Verilog (open-source)

```bash
# Booth multiplier
iverilog -o sim_booth sourcecode/rtl/booth_multiplier.v sourcecode/tb/tb_booth_multiplier.v && vvp sim_booth

# Accumulator
iverilog -o sim_acc sourcecode/rtl/accumulator.v sourcecode/tb/tb_accumulator.v && vvp sim_acc

# Pipelined MAC
iverilog -o sim_mac sourcecode/rtl/booth_multiplier.v sourcecode/rtl/accumulator.v sourcecode/rtl/pipelined_mac.v sourcecode/tb/tb_pipelined_mac.v && vvp sim_mac

# Conv engine
iverilog -o sim_conv sourcecode/rtl/booth_multiplier.v sourcecode/rtl/accumulator.v sourcecode/rtl/pipelined_mac.v sourcecode/rtl/conv_engine.v sourcecode/tb/tb_conv_engine.v && vvp sim_conv
```

---

## Test Coverage

| Testbench | Tests |
|-----------|-------|
| `tb_booth_multiplier` | +×+, −×+, −×−, zero, max/min operands, 20 random cases |
| `tb_accumulator` | Basic sum, synchronous clear, valid gating, overflow detection |
| `tb_pipelined_mac` | Single MAC, 3-element dot product, 9-element dot product, negative values |
| `tb_conv_engine` | All-ones kernel, sum-of-squares, Sobel H/V kernels, back-to-back convolutions, identity kernel |

---

## Phase 2 Preview (ASIC)

After functional verification:
1. **Remove FPGA primitives** — RTL is already ASIC-clean (no `BUFG`, `DSP48` inferences)
2. **Genus synthesis** — apply SDC constraints (`create_clock`, `set_input_delay`, `set_output_delay`)
3. **Innovus P&R** — floorplan, placement, CTS, routing
4. **Tempus STA** — post-layout timing closure
5. **GDS-II export** and PPA reporting

---

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Multiplier algorithm | Radix-2 Booth | Handles signed operands natively, good for ASIC area |
| Pipeline depth | 2 stages | Balances latency vs. throughput for 3×3 kernel |
| Accumulator width | 32-bit | Prevents overflow for 9× 16b×16b products (max 9 × 32767² ≈ 9.6 × 10⁹ < 2³¹) |
| Data format | 16-bit signed fixed-point | Matches project spec; sufficient for CNN inference |
| clear alignment | Delayed 1 cycle in MAC | Synchronizes accumulator reset with pipeline output |
