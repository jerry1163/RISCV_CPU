# RISC-V CPU FPGA Project

Vivado 2019.2 project for a small RV32IM five-stage pipelined CPU.

The CPU runs from a True Dual Port BRAM in the FPGA top level, and the repository also includes an automatic behavioral simulation testbench that can run `test7` and `test9` without regenerating the BRAM IP.

## Current Status

- Vivado project: `RISCV_FPGA.xpr`
- Device: `xc7k325tffg900-2` (Kintex-7)
- Synthesis top: `riscv_mcu_tdpram_top`
- Default simulation top: `riscv_cpu_auto_tb`
- CPU core: `RISCV_FPGA.srcs/sources_1/new/riscv_cpu.v`
- RV32M unit: `RISCV_FPGA.srcs/sources_1/new/riscv_mdu.v`
- Automatic testbench: `RISCV_FPGA.srcs/sim_1/new/riscv_cpu_auto_tb.v`
- Main programs: `test7_tdp.coe`, `test9.coe`
- BRAM IP: `RISCV_FPGA.srcs/sources_1/ip/tdp_bram/tdp_bram.xci`
- Clock IP: `RISCV_FPGA.srcs/sources_1/ip/clk_wiz_sys/clk_wiz_sys.xci`

The current timing target in the checked-in project is 210 MHz on Kintex-7.

## CPU Features

- IF / ID / EX / MEM / WB five-stage pipeline
- EX/MEM and MEM/WB forwarding
- Same-cycle WB-to-ID register read bypass
- Load-use stall handling
- EX-stage branch, JAL, and JALR flush
- Byte, halfword, and word load/store alignment
- True Dual Port BRAM instruction/data access in the FPGA top
- RV32M support through a pure RTL iterative MDU:
  - `mul`, `mulh`, `mulhsu`, `mulhu`
  - `div`, `divu`, `rem`, `remu`

The MDU is intentionally simple and timing-friendly. Normal RV32I instructions do not go through the MDU path.

## Quick Start

Clone and open the Vivado project:

```powershell
git clone https://github.com/jerry1163/RISCV_CPU.git
cd RISCV_CPU
```

Open:

```text
RISCV_FPGA.xpr
```

If Vivado reports stale IP output products for `clk_wiz_sys` or `tdp_bram`, use `Reports > Report IP Status` and generate output products.

## Behavioral Simulation

The default simulation top is `riscv_cpu_auto_tb`. It directly instantiates `riscv_cpu`, loads the COE file into a behavioral synchronous RAM, and automatically checks the final register and memory results.

Run default `test7` in Vivado Tcl Console:

```tcl
close_sim -force
set_property top riscv_cpu_auto_tb [get_filesets sim_1]
set_property verilog_define {} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
```

Expected console output:

```text
Loaded 79 words from test7_tdp.coe for test7
PASS test7 at cycle 96
```

Run `test9`:

```tcl
close_sim -force
set_property top riscv_cpu_auto_tb [get_filesets sim_1]
set_property verilog_define {TEST9} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
```

Expected console output:

```text
Loaded 26 words from test9.coe for test9
PASS test9 at cycle 369
```

Useful waveform signals:

- `riscv_cpu_auto_tb/test_pass`
- `riscv_cpu_auto_tb/cycle`
- `riscv_cpu_auto_tb/dbg_pc`
- `riscv_cpu_auto_tb/dbg_x01` through `dbg_x31`
- `riscv_cpu_auto_tb/uut`
- `riscv_cpu_auto_tb/uut/riscv_mdu_inst`
- `riscv_cpu_auto_tb/ram`

## Python Reference Simulator

The Python simulator is useful as a fast golden model:

```powershell
python riscv_single_cycle_sim.py --tdp test7_tdp.coe --max-cycles 300
python riscv_single_cycle_sim.py --pipeline --tdp test7_tdp.coe --max-cycles 400
python riscv_single_cycle_sim.py --tdp test9.coe --max-cycles 100 --dump-words 16
python riscv_single_cycle_sim.py --pipeline --tdp test9.coe --max-cycles 500 --dump-words 16
```

## Recreate the Project

If the checked-in `.xpr` contains stale local paths, recreate from repository-relative paths in Vivado Tcl Console:

```tcl
cd <repo-root>
source scripts/recreate_project.tcl
```

The recreate script targets `xc7k325tffg900-2`, adds the RTL, COE programs, automatic testbench, `clk_wiz_sys`, and `tdp_bram`.

## Notes Before Bitstream

Before generating a board bitstream, add board-specific `LOC` and `IOSTANDARD` constraints for `CLK_FPGA` and `PA[31:0]`. The current constraints are not a complete board pinout.
