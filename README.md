# RISC-V FPGA CPU

This repository contains a small RV32I CPU project for Vivado, together with
the Test6/Test7 memory images and a Python single-cycle reference simulator.

## Contents

- `RISCV_FPGA.srcs/sources_1/new/`
  - `riscv_cpu.v`: top-level single-cycle CPU datapath
  - `riscv_inst_decode.v`: instruction decoder and control signals
  - `riscv_imm_gen.v`: immediate generator
  - `riscv_alu_decode.v`: ALU control decoder
  - `riscv_alu.v`: ALU
  - `riscv_reg_file.v`: register file
  - `riscv_pc_gen.v`: branch/jump PC generator
- `RISCV_FPGA.srcs/sim_1/new/riscv_cpu_no_pipeline_tb.v`: simple Verilog testbench
- `test6.s`, `test6.coe`, `test6_data.coe`: Test6 program and data
- `test7.coe`, `test7_data.coe`, `test7_tdp.coe`: Test7 split and unified-memory images
- `riscv_single_cycle_sim.py`: Python reference model used as a golden simulator before Verilog changes

## Current CPU

The current Verilog CPU is a single-cycle RV32I subset implementation. It
supports the core instructions used by Test6, including arithmetic, logic,
load/store, branches, `jal`, `jalr`, `lui`, and `auipc`.

Test7 adds extra memory behavior such as byte/halfword load and store
operations. The Python model already supports the Test7 instruction set and is
intended to guide the next Verilog update.

## Python Golden Model

Run the unified-memory Test7 image:

```powershell
python .\riscv_single_cycle_sim.py --tdp .\test7_tdp.coe --dump-words 30
```

Print the full executed instruction trace:

```powershell
python .\riscv_single_cycle_sim.py --tdp .\test7_tdp.coe --trace
```

Expected high-level result for `test7_tdp.coe`:

```text
cycles: 68
halt: self-loop jal at 0x00000114
pc: 0x00000114
```

Key final register values:

```text
x01=0x87654321
x02=0x04040404
x06=0x00000028
x07=0x00000030
x25=0x87654088
x26=0xffffffef
x27=0xffffcdef
x28=0x000000ef
x29=0x0000cdef
x31=0x00000140
```

## Next Step

The next development step is to evolve the Python model from single-cycle
execution into a five-stage pipeline model, add forwarding/stall/flush logic in
Python first, and then implement the verified behavior in Verilog.

