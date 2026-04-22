# test7 BRAM IP initialization notes

这次流水线 CPU 验证使用的是 `test7_tdp.coe`，而工程里的 `tdp_bram` 是 Block Memory Generator True Dual Port RAM。需要注意：仿真模型实际加载的是生成后的 `tdp_bram.mif`，不是每次直接读取 COE。

## 修改内容

- `RISCV_FPGA.srcs/sources_1/ip/tdp_bram/tdp_bram.xci`
  - `PARAM_VALUE.Coe_File` 从原来的 test6 初始化源改成 `../../../../test7_tdp.coe`。
  - 这样重新生成 IP output products 时，Vivado 会以 test7 作为初始化来源。

- `RISCV_FPGA.srcs/sources_1/ip/tdp_bram/tdp_bram.mif`
  - 已由 `test7_tdp.coe` 转换得到。
  - COE 是 16 进制 word；MIF 是 32 位二进制一行一个 word。
  - 第一行应为 `00010100000000000000111110010011`，对应 test7 第一条指令 `14000F93`。

- `RISCV_FPGA.srcs/sources_1/ip/tdp_bram/sim/tdp_bram.v`
  - IP 仿真模型里 `C_INIT_FILE_NAME` 仍然是 `tdp_bram.mif`。
  - 这意味着 xsim 运行时要保证同名 MIF 文件内容已经是 test7。

## 可能的问题

如果只改 `test7_tdp.coe`，但没有重新生成 IP 或同步 `tdp_bram.mif`，仿真可能仍然加载旧的 test6 内容。判断方法是看 `tdp_bram.mif` 第一行：

- test7 第一行：`00010100000000000000111110010011` (`14000F93`)
- test6 第一行：`10000111011001010100000010110111` (`876540B7`)

所以这不是 CPU 逻辑问题，而是 Vivado IP 初始化文件同步问题。比较稳妥的流程是：改 COE 路径或 IP 配置后，重新生成 output products，并确认生成的 `tdp_bram.mif` 已经变成 test7。

## 验证方式

不要用旧的 `dram_dump.txt` 做标准。当前验证脚本 `pipeline_check.tcl` 直接在 xsim 里读取寄存器堆，关键结果应为：

```text
x06=00000028
x07=00000030
x24=00000000
x26=ffffffef
x27=ffffcdef
x28=000000ef
x29=0000cdef
x30=00000118
x31=00000140
```
