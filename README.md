# RISC-V 五级流水线 CPU FPGA 工程

这个仓库是 Vivado 2019.2 工程，目标是在 True Dual Port BRAM 上运行 `test7_tdp.coe`，实现一个 RV32I 子集的五级流水线 CPU。

## 当前状态

- 工程文件：`RISCV_FPGA.xpr`
- 综合顶层：`riscv_mcu_tdpram_top`
- 仿真顶层：`riscv_mcu_top_tb`
- CPU 核心：`RISCV_FPGA.srcs/sources_1/new/riscv_cpu.v`
- 统一指令/数据初始化：`test7_tdp.coe`
- BRAM 初始化文件：`RISCV_FPGA.srcs/sources_1/ip/tdp_bram/tdp_bram.mif`

CPU 已经从单周期版本改成五级流水线版本，包含：

- IF / ID / EX / MEM / WB 五级流水线寄存器
- EX 阶段转发
- load-use 冒险暂停
- jal / jalr / branch 的 flush
- `lb/lh/lw/lbu/lhu`
- `sb/sh/sw`
- True Dual Port BRAM 同步读一拍延迟适配

## Vivado 使用方法

1. 用 Vivado 打开：

   ```text
   RISCV_FPGA.xpr
   ```

2. 确认综合顶层是：

   ```text
   riscv_mcu_tdpram_top
   ```

3. 确认仿真顶层是：

   ```text
   riscv_mcu_top_tb
   ```

4. 如果 Vivado 提示 IP output products 过期，选择重新生成。

5. 点击 `Run Synthesis` 运行综合。

## 仿真检查

命令行可以在 xsim 目录运行：

```powershell
xsim riscv_mcu_top_tb_behav -tclbatch pipeline_check.tcl -log pipeline_check.log
```

`pipeline_check.tcl` 会直接读取寄存器堆，不依赖旧的 `dram_dump.txt`。

test7 的关键最终结果应为：

```text
x01=87654321
x02=04040404
x06=00000028
x07=00000030
x24=00000000
x25=87654088
x26=ffffffef
x27=ffffcdef
x28=000000ef
x29=0000cdef
x30=00000118
x31=00000140
```

## BRAM 初始化说明

`tdp_bram` 是 Vivado Block Memory Generator。工程里同时保留：

- `test7_tdp.coe`：IP 的初始化来源
- `tdp_bram.mif`：xsim 仿真模型实际加载的初始化文件

如果重新生成 IP，需要确认 `tdp_bram.mif` 第一行仍然是：

```text
00010100000000000000111110010011
```

它对应 `test7_tdp.coe` 的第一条指令：

```text
14000F93
```
