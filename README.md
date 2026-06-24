# RV32IM 五级流水线 CPU（Vivado / Kintex-7）

这是一个使用 Verilog 实现的 RV32IM 五级流水线 CPU 工程。工程以教学、结构分析和 FPGA 性能优化为主要目标，能够在 Vivado 2019.2 中运行 `test7` 和 `test9`，并通过自动 testbench 检查寄存器、内存和性能计数器。

当前版本包括：

- RV32I 整数指令子集。
- RV32M 乘法、除法和余数指令。
- IF、ID、EX、MEM、WB 五级流水线。
- EX/MEM 和 MEM/WB 数据前递。
- WB 到 ID 的同周期寄存器旁路。
- Load-use 冒险检测和流水线停顿。
- 32 项二位饱和计数器 BHT。
- JAL 和条件分支预测。
- JALR 的 EX 阶段恢复。
- True Dual Port BRAM 指令和数据访问。
- 可切换 test7/test9 的自动检查 testbench。
- IPC、stall、flush、分支预测和 Amdahl 定律性能统计。
- 单周期 Python 功能模型和五级流水线 Python 教学模型。

## 1. 当前工程状态

| 项目 | 当前配置 |
|---|---|
| Vivado 版本 | 2019.2 |
| FPGA | `xc7k325tffg900-2`（Kintex-7） |
| 综合顶层 | `riscv_mcu_tdpram_top` |
| 默认仿真顶层 | `riscv_cpu_auto_tb` |
| 输入时钟 | 100 MHz |
| CPU 时钟 | 200 MHz |
| CPU 时钟周期 | 5 ns |
| 实现策略 | `Performance_Explore` |
| test7 | PASS，79 个性能统计周期，68 条指令 |
| test9 | PASS，361 个性能统计周期，26 条指令 |
| 路由后 WNS | +0.124 ns |
| test7 IPC | 0.8608 |
| test9 IPC | 0.0720 |

路由后 200 MHz 时序已经满足。清理遗留的重复时钟约束后，当前关键路径从 BHT 预测状态进入指令 BRAM 使能，数据路径延迟约 4.154 ns，其中布线延迟约占 82.5%。

## 2. 第一次使用：最快运行方法

### 2.1 克隆工程

```powershell
git clone https://github.com/jerry1163/RISCV_CPU.git
cd RISCV_CPU
```

### 2.2 打开 Vivado 工程

使用 Vivado 2019.2 打开：

```text
RISCV_FPGA.xpr
```

综合顶层应为：

```text
riscv_mcu_tdpram_top
```

仿真顶层应为：

```text
riscv_cpu_auto_tb
```

如果 Vivado 提示 `clk_wiz_sys` 或 `tdp_bram` 的 output products 缺失或过期：

1. 打开 `Reports > Report IP Status`。
2. 选中对应 IP。
3. 执行 `Generate Output Products`。
4. 再执行 `update_compile_order` 或重新启动仿真。

自动 testbench 直接例化 CPU 并使用行为级同步 RAM，因此运行 test7/test9 的行为仿真不依赖 BRAM IP 仿真模型。

## 3. 为什么需要五级流水线

不使用流水线时，一条指令需要依次完成取指、译码、执行、访存和写回。为了在一个时钟周期内完成全部工作，时钟周期必须大于所有阶段组合延迟之和。

五级流水线在阶段之间加入寄存器，让多条指令重叠执行：

```text
周期        1      2      3      4      5      6      7
指令 I1    IF     ID     EX     MEM    WB
指令 I2           IF     ID     EX     MEM    WB
指令 I3                  IF     ID     EX     MEM    WB
```

流水线不会减少单条指令从 IF 到 WB 的基本级数，但会提高单位时间内完成的指令数。

理想情况下：

```text
IPC = 每周期完成指令数 = 1
CPI = 每条指令平均周期数 = 1
```

实际 CPU 会因为数据相关、控制相关、存储器延迟和多周期运算出现气泡：

```text
总周期数 = 有效指令周期 + stall 周期 + flush 周期 + 启动/排空开销
IPC = retired instructions / total cycles
CPU 性能约等于 IPC × 时钟频率
```

因此本工程的优化有两个方向：

- 提高 IPC：减少 load-use stall、控制流气泡和 MDU stall。
- 提高频率：缩短最慢寄存器到寄存器组合路径。

## 4. 本工程的五级流水线

### 4.1 IF：Instruction Fetch

IF 阶段负责产生指令地址并向指令 BRAM 发起请求。

核心状态：

- `pc`：下一次请求的指令地址。
- `imem_resp_pc`：与同步 BRAM 返回指令对应的 PC。
- `imem_resp_valid`：当前 BRAM 返回值是否有效。
- `redirect_fetch_advance`：预测跳转后的连续取指修正状态。
- `fetch_buf_valid`：ID 停顿时保存已经返回的下一条指令。

True Dual Port BRAM 是同步读存储器，地址在时钟沿被采样，数据在随后一个周期返回。因此不能只保存一个 `pc`，还必须保存“返回的指令属于哪个地址”。

```text
请求地址 pc[N] --时钟沿--> BRAM
                         |
                         +-- 下一周期返回 inst[N]
```

当 ID 因 load-use 或 MDU 停顿时，BRAM 仍可能返回下一条指令。为避免丢失这条指令，CPU 使用一个一项 fetch buffer 保存 `PC + instruction`。

### 4.2 IF/ID 流水线寄存器

`IF/ID` 保存：

- `if_id_valid`
- `if_id_pc`
- `if_id_inst`

`valid=0` 表示该级是气泡。CPU 不需要给气泡创造一条特殊指令，只要后续控制逻辑检查 valid 即可阻止写寄存器、写内存和错误跳转。

### 4.3 ID：Instruction Decode

ID 阶段完成：

- 提取 `rs1`、`rs2`、`rd`。
- 识别 opcode、funct3、funct7。
- 产生立即数。
- 读取寄存器堆。
- 产生 ALU、访存、写回和控制流控制信号。
- 计算数据前递选择。
- 查询条件分支 BHT。
- 对 JAL 和预测 taken 的条件分支发起重定向。

主要模块：

| 模块 | 作用 |
|---|---|
| `riscv_inst_decode.v` | 主译码和控制信号生成 |
| `riscv_imm_gen.v` | I/S/B/U/J 型立即数生成 |
| `riscv_alu_decode.v` | 根据 alu_opcode、funct3、funct7 选择 ALU 操作 |
| `riscv_reg_file.v` | 32×32 位整数寄存器堆 |

### 4.4 ID/EX 流水线寄存器

`ID/EX` 保存执行阶段需要的全部信息：

- PC 和原始指令。
- rs1、rs2、rd 编号。
- rs1、rs2 读取值。
- funct3、funct7。
- ALU 控制和立即数选择。
- 寄存器写使能及写回来源。
- load/store 控制。
- 分支类型和预测结果。
- MDU 类型和操作码。
- 前递选择。

控制流 flush 或 load-use stall 会将 `id_ex_valid` 清零，从而在 EX 插入气泡。

### 4.5 EX：Execute

EX 是当前 CPU 组合逻辑最集中的阶段，负责：

- ALU 运算。
- 前递操作数选择。
- load/store 有效地址计算。
- store 数据对齐和字节写掩码生成。
- 条件分支比较。
- JAL/JALR 目标地址计算。
- 预测结果与真实结果比较。
- 启动和等待 MDU。
- 选择写回候选值。

ALU 支持：

```text
ADD SUB
AND OR XOR
SLL SRL SRA
SLT SLTU
```

分支比较没有只依赖 ALU 的 zero flag，而是直接对经过专用分支前递的操作数进行有符号或无符号比较。

### 4.6 EX/MEM 流水线寄存器

`EX/MEM` 保存：

- 指令是否有效。
- rd 编号和写回使能。
- 写回来源。
- 是否为 load。
- load 宽度和无符号属性。
- 地址低两位。
- EX 计算得到的写回数据。

数据 BRAM 的同步读数据在 MEM 阶段使用，随后写入 MEM/WB。

### 4.7 MEM：Memory

MEM 阶段完成 load 数据选择和符号扩展：

- `lb`：选择一个字节并符号扩展。
- `lbu`：选择一个字节并零扩展。
- `lh`：选择低/高半字并符号扩展。
- `lhu`：选择低/高半字并零扩展。
- `lw`：使用完整 32 位数据。

store 的地址、数据和字节写掩码在 EX 计算后送到 BRAM 端口，在 EX/MEM 边界完成写入请求。

### 4.8 MEM/WB 与 WB

MEM/WB 保存最终写回信息。写回来源包括：

| 来源 | 典型指令 |
|---|---|
| ALU/MDU | 算术、逻辑、乘除法 |
| Memory | load |
| PC | JAL、JALR、AUIPC |
| Immediate | LUI |

`mem_wb_do_write` 只有在以下条件同时成立时有效：

- MEM/WB 指令有效。
- 译码要求写寄存器。
- rd 不是 x0。

寄存器堆还会在每个时钟沿强制 `x0=0`。

## 5. 总体数据通路

```text
                         +--------------------+
                         |  Branch Predictor  |
                         |  32-entry 2-bit BHT|
                         +---------+----------+
                                   |
                                   v
+------+    +-------+    +-------+    +--------+    +-------+
|  IF  | -> | IF/ID | -> | ID/EX | -> | EX/MEM | -> |MEM/WB |
+------+    +-------+    +-------+    +--------+    +---+---+
   |           |             |             |             |
   |           |             +--> ALU      +--> Load     |
   |           |             +--> Branch   |    align    |
   |           |             +--> MDU      |             |
   |           |             +--> Address  |             |
   |           |                                           |
   |           +--> Decode / Immediate / Register File     |
   |                                                       |
   +<---------------- PC redirect                           |
                                                           v
                                                    Register File
```

前递网络：

```text
EX/MEM result --------+
                      +--> EX operand mux --> ALU / address / MDU
MEM/WB result --------+

MEM/WB result ------------> ID register read bypass
```

## 6. 支持的指令

### 6.1 RV32I

| 类型 | 指令 |
|---|---|
| R-type | `add sub sll slt sltu xor srl sra or and` |
| I-type ALU | `addi slli slti sltiu xori srli srai ori andi` |
| Load | `lb lh lw lbu lhu` |
| Store | `sb sh sw` |
| Branch | `beq bne blt bge bltu bgeu` |
| Jump | `jal jalr` |
| Upper immediate | `lui auipc` |

System/CSR、异常、特权级和中断不是当前测试目标。译码器对 system opcode 只保留保守控制，不构成完整的 RISC-V 特权实现。

### 6.2 RV32M

| funct3 | 指令 | 结果 |
|---:|---|---|
| 000 | `mul` | 乘积低 32 位 |
| 001 | `mulh` | signed×signed 高 32 位 |
| 010 | `mulhsu` | signed×unsigned 高 32 位 |
| 011 | `mulhu` | unsigned×unsigned 高 32 位 |
| 100 | `div` | 有符号商 |
| 101 | `divu` | 无符号商 |
| 110 | `rem` | 有符号余数 |
| 111 | `remu` | 无符号余数 |

RV32M 指令由 `opcode=0110011` 且 `funct7=0000001` 识别。

## 7. 数据冒险与前递

### 7.1 什么是 RAW 冒险

例如：

```assembly
add x5, x1, x2
sub x6, x5, x3
```

第二条指令在 ID 读取 x5 时，第一条指令可能还没有写回。如果不处理，sub 会读到旧值。

本工程使用两级前递：

- EX/MEM 到 EX。
- MEM/WB 到 EX。

优先级：

```text
最新的 EX/MEM 结果 > 较旧的 MEM/WB 结果 > ID/EX 保存的寄存器值
```

只有能够及时得到结果的指令才允许从 EX/MEM 前递。load 的数据在 MEM 才返回，因此不能作为普通 EX/MEM ALU 结果前递。

### 7.2 WB 到 ID 的同周期旁路

寄存器堆在时钟沿写入，而 ID 组合读可能在同一周期需要这个值。CPU 在寄存器堆输出之外增加：

```text
if MEM/WB.rd == ID.rs:
    ID operand = MEM/WB write-back data
else:
    ID operand = register-file data
```

这避免了 WB 与 ID 同周期冲突造成的额外停顿。

### 7.3 Load-use stall

例如：

```assembly
lw   x5, 0(x1)
add  x6, x5, x2
```

load 数据在下一阶段才返回，单纯前递来不及。检测条件大致为：

```text
ID/EX 是 load
且 rd != x0
且 IF/ID 真实使用相同的 rs1 或 rs2
```

处理方式：

- PC 保持。
- IF/ID 保持。
- 已返回但暂时无法进入 ID 的指令保存到 fetch buffer。
- ID/EX 插入一个气泡。
- load 继续向 MEM 前进。

test7 目前有 3 个 load-use stall。

## 8. 控制冒险与分支预测

### 8.1 为什么分支会产生气泡

条件分支的真实结果在 EX 才知道。如果一直顺序取指，分支后面的若干指令可能已经进入 IF 和 ID。方向错误时必须清除这些错误路径指令并从正确 PC 重新取指。

### 8.2 当前预测策略

当前策略是：

| 控制指令 | 预测 |
|---|---|
| JAL | 始终预测 taken |
| JALR | 不预测，在 EX 恢复 |
| 条件分支首次出现 | 前向预测 taken，后向预测 not-taken |
| 条件分支已有历史 | 使用 32 项二位饱和计数器 BHT |

这里的“前向 taken、后向 not-taken”是针对 test7 指令分布选择的策略，不是传统教材中常见的“后向 taken、前向 not-taken”。

### 8.3 32 项 BHT

定义：

```verilog
reg [31:0] bht_valid;
reg [1:0]  bht_counter [0:31];
wire [4:0] id_bht_idx = if_id_pc[6:2];
```

使用 PC 的 `[6:2]` 作为索引：

- 低两位不使用，因为 32 位指令地址按 4 字节对齐。
- 5 位索引对应 32 项。
- 没有 tag，因此不同 PC 可能映射到同一项并产生 alias。

二位计数器状态：

| 状态 | 含义 | 预测 |
|---|---|---|
| 00 | 强不跳 | not-taken |
| 01 | 弱不跳 | not-taken |
| 10 | 弱跳转 | taken |
| 11 | 强跳转 | taken |

真实分支结果在 EX 得到后更新：

- taken：计数器饱和加一。
- not-taken：计数器饱和减一。
- 第一次执行：taken 初始化为 10，not-taken 初始化为 01。

### 8.4 误预测检测

ID 阶段的预测结果保存在 `id_ex_pred_taken`。

EX 阶段计算：

```text
actual_taken =
    JAL
    or JALR
    or (conditional branch and branch_taken)

mispredict =
    predicted_taken != actual_taken
```

恢复地址：

```text
taken     -> branch/jump target
not-taken -> branch PC + 4
```

当前 `ex_fast_redirect=0`，误预测使用慢恢复。这样做是为了避免 EX 的晚到比较结果直接进入指令 BRAM 地址关键路径。

### 8.5 当前控制流性能

test7：

- 条件分支 5 条。
- 条件分支误预测 0 次。
- 条件分支预测准确率 100%。
- 预测 taken 重定向 3 次。
- JALR 慢恢复 1 次。
- 控制流代价 6 周期。

test7 中每个条件分支只执行一次，因此首次静态策略贡献最大，BHT 学习并没有机会在同一分支的后续迭代中发挥明显作用。

## 9. 多周期乘除法单元 MDU

当前数据通路使用 `riscv_mdu.v`，不依赖 Divider Generator 或 Multiplier Generator IP。

接口：

```verilog
start
op[2:0]
din_a
din_b
busy
done
result
```

状态机：

```text
ST_IDLE
  | start multiply
  v
ST_MUL  -- 32 次移位累加 --> done

ST_IDLE
  | start divide/remainder
  v
ST_DIV  -- 32 次恢复除法 --> done
```

### 9.1 乘法

乘法采用移位累加：

- `mul_acc` 保存部分和。
- `mul_multiplicand` 每周期左移。
- `mul_multiplier` 每周期右移。
- multiplier 最低位为 1 时将 multiplicand 加到累加器。
- signed 高位乘法先取绝对值，最后统一恢复符号。

### 9.2 除法

除法采用逐位恢复算法：

- remainder 左移并引入 dividend 最高位。
- 比较 remainder 与 divisor。
- 足够大时执行减法，并在 quotient 低位写 1。
- 重复 32 次。
- signed 运算先对操作数取绝对值，结束后恢复商和余数符号。

### 9.3 RISC-V 特殊情况

实现了 RV32M 规定的重要边界行为：

| 情况 | DIV/DIVU | REM/REMU |
|---|---|---|
| 除数为 0 | `0xffffffff` | 原被除数 |
| `0x80000000 / -1` | `0x80000000` | 0 |

### 9.4 MDU 对流水线的影响

MDU busy 时：

- PC 保持。
- IF/ID 保持。
- 当前 MDU 指令保持在 ID/EX。
- EX/MEM 插入气泡，避免同一条 MDU 指令重复提交。
- fetch buffer 保存同步指令 RAM 已经返回的指令。
- done 后结果通过正常 EX/MEM、MEM/WB 路径写回。

test9 包含 10 条 MDU 指令，当前统计到 330 个 MDU stall 周期，因此 test9 的主要瓶颈是迭代 MDU，而不是分支预测。

## 10. 存储系统

### 10.1 True Dual Port BRAM

FPGA 顶层使用一个 True Dual Port BRAM：

| 端口 | 用途 |
|---|---|
| Port A | 指令读取 |
| Port B | 数据读取和写入 |

物理结构是统一存储器，但 CPU 接口表现为同时存在的指令端口和数据端口，因此可以在同一周期取指并进行数据访问。

BRAM 地址使用 `address[16:2]`：

- 15 位 word index。
- 32768 个 32 位 word。
- 物理容量 128 KiB。

低地址 RAM 写使能还检查 `address[31:20]==0`。由于 BRAM 实际只使用 `[16:2]`，低 1 MiB 范围内更高地址位不会进入 BRAM 索引，软件应在已验证的 128 KiB 范围内使用内存，避免地址 alias。

### 10.2 小端序和字节掩码

RISC-V 使用 little-endian：

```text
最低地址 -> word[7:0]
最高地址 -> word[31:24]
```

store 根据地址低两位移动数据并生成写掩码：

```text
SB: 0001 / 0010 / 0100 / 1000
SH: 0011 / 1100
SW: 1111
```

### 10.3 简单 MMIO

顶层保留两个 MMIO 地址：

| 地址 | 功能 |
|---|---|
| `0x80000000` | 读 PA 输入或写输出数据 `pout` |
| `0x80000001` | 写 PA 三态控制 `pa_t` |

`pa_t` 的某一位为 1 时，对应 PA 引脚为高阻；为 0 时输出 `pout` 对应位。

生成实际板级 bitstream 前仍需补全 `CLK_FPGA` 和 `PA[31:0]` 的 LOC、IOSTANDARD 等板级约束。

## 11. 主要文件说明

### 11.1 当前有效 RTL

| 文件 | 作用 |
|---|---|
| `RISCV_FPGA.srcs/sources_1/new/riscv_cpu.v` | CPU 数据通路、流水线、冒险和预测核心 |
| `riscv_inst_decode.v` | 主译码 |
| `riscv_imm_gen.v` | 立即数生成 |
| `riscv_alu_decode.v` | ALU 控制译码 |
| `riscv_alu.v` | 整数 ALU |
| `riscv_reg_file.v` | 32×32 位寄存器堆 |
| `riscv_mdu.v` | 当前 RV32M 迭代乘除法单元 |
| `riscv_mcu_tdpram_top.v` | Clock Wizard、CPU、BRAM 和 PA 顶层连接 |

### 11.2 仿真和工具

| 文件 | 作用 |
|---|---|
| `RISCV_FPGA.srcs/sim_1/new/riscv_cpu_auto_tb.v` | test7/test9 自动 testbench |
| `riscv_single_cycle_sim.py` | Python 功能参考模型和教学流水线模型 |
| `scripts/recreate_project.tcl` | 从相对路径重建 Vivado 工程 |
| `scripts/run_impl_current.tcl` | 自动综合、实现和生成路由后时序报告 |
| `test7_tdp.coe` | test7 统一指令/数据镜像 |
| `test9.coe` | test9 RV32M 测试镜像 |
| `test9.s` | test9 汇编源码 |

### 11.3 历史遗留但不在当前数据通路中的文件

以下文件不是当前 CPU 的乘除法实现：

- `riscv_div.v`
- `riscv_mul_para.v`
- `div_gen_0` IP
- `mult_32x32` IP
- 对应的 demo testbench

当前 `riscv_cpu.v` 只例化 `riscv_mdu`。阅读和调试时应从 `riscv_mdu.v` 开始，不要把旧 IP 路径当成当前实现。

`riscv_pc_gen.v` 也是早期独立 PC 生成模块；当前取指、预测和恢复逻辑已经直接集成在 `riscv_cpu.v`。

## 12. 自动行为仿真

### 12.1 testbench 做了什么

`riscv_cpu_auto_tb`：

- 直接例化 `riscv_cpu`。
- 建立 32768×32 位行为级同步 RAM。
- 从 COE 文件加载指令和数据。
- 模拟字节写掩码。
- 检测程序末尾 `jal x30, 0` 自循环。
- 等待流水线排空。
- 检查寄存器和内存。
- 输出 PASS/FAIL。
- 输出性能计数器和 Amdahl 理论收益。

testbench 中的 `always #5` 只决定仿真时间刻度。性能计数按“周期数”统计，吞吐率使用 `CPU_FREQ_MHZ=200.0` 换算，不代表行为仿真本身真的在模拟门级 200 MHz 延迟。

### 12.2 运行 test7

在 Vivado Tcl Console 中执行：

```tcl
close_sim -force
set_property top riscv_cpu_auto_tb [get_filesets sim_1]
set_property verilog_define {} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
```

关键输出：

```text
Loaded 79 words from test7_tdp.coe for test7
PERF cycles=79 instructions=68 IPC=0.8608 CPI=1.1618 throughput=172.15_MIPS
PERF load_use_stall_cycles=3 mdu_instructions=0 mdu_stall_cycles=0 predicted_taken_redirects=3
PERF branch_predictions=5 branch_mispredictions=0 prediction_accuracy=100.00%
PASS test7 at cycle 90
```

`PASS at cycle 90` 包含 halt 检测后的检查等待；性能计数器在 halt 指令完成 EX 时冻结，所以有效性能周期是 79。

### 12.3 运行 test9

```tcl
close_sim -force
set_property top riscv_cpu_auto_tb [get_filesets sim_1]
set_property verilog_define {TEST9} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
```

关键输出：

```text
Loaded 26 words from test9.coe for test9
PERF cycles=361 instructions=26 IPC=0.0720 CPI=13.8846 throughput=14.40_MIPS
PERF load_use_stall_cycles=0 mdu_instructions=10 mdu_stall_cycles=330
PASS test9 at cycle 372
```

切回 test7 时一定要清除宏：

```tcl
set_property verilog_define {} [get_filesets sim_1]
```

### 12.4 推荐波形

顶层：

- `riscv_cpu_auto_tb/clk`
- `riscv_cpu_auto_tb/rst_n`
- `riscv_cpu_auto_tb/cycle`
- `riscv_cpu_auto_tb/test_done`
- `riscv_cpu_auto_tb/test_pass`

取指和流水线：

- `uut/pc`
- `uut/imem_resp_pc`
- `uut/imem_resp_valid`
- `uut/if_id_valid`
- `uut/if_id_pc`
- `uut/if_id_inst`
- `uut/id_ex_valid`
- `uut/id_ex_pc`
- `uut/id_ex_inst`
- `uut/ex_mem_valid`
- `uut/mem_wb_valid`

冒险和控制流：

- `uut/load_use_stall`
- `uut/mdu_stall`
- `uut/id_predict_fire`
- `uut/id_ex_pred_taken`
- `uut/branch_taken`
- `uut/ex_actual_taken`
- `uut/ex_flush`
- `uut/ex_recovery_target`

MDU：

- `uut/mdu_start`
- `uut/mdu_busy`
- `uut/mdu_done`
- `uut/mdu_result`
- `uut/riscv_mdu_inst/state`
- `uut/riscv_mdu_inst/count`

寄存器：

- testbench 提供 `dbg_x01` 至部分常用寄存器。
- 完整寄存器可以展开 `uut/riscv_reg_file_inst/x` 查看。

### 12.5 常见 XSIM 问题

仿真已经在运行：

```text
Simulator for snapshot ... is already running
```

处理：

```tcl
close_sim -force
launch_simulation
```

波形配置被修改，无法关闭：

```text
Wave configuration has been modified
```

处理：

```tcl
close_sim -force
```

找不到 design unit：

```text
Cannot find design unit xil_defaultlib.riscv_cpu_auto_tb
```

处理：

```tcl
set_property top riscv_cpu_auto_tb [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_sim -force
launch_simulation
```

仍然失败时，确认 `riscv_cpu_auto_tb.v` 已加入 `sim_1`，而不是 `sources_1`。

## 13. test7 与 test9

### 13.1 test7

test7 主要覆盖 RV32I：

- 算术和逻辑运算。
- 有符号和无符号比较。
- 左移、逻辑右移、算术右移。
- byte/halfword/word load/store。
- 符号扩展和零扩展。
- JAL、JALR 和条件分支。
- RAW 前递。
- load-use stall。
- 分支预测。

最终检查值集中在 testbench 的 `check_test7` task 中。

### 13.2 test9

test9 主要覆盖 RV32M：

- 四种乘法。
- signed/unsigned 除法。
- signed/unsigned 余数。
- 除零。
- `INT_MIN / -1` 溢出边界。
- MDU 结果写回和流水线停顿。

汇编源文件为 `test9.s`，最终检查值位于 `check_test9` task。

## 14. 性能计数器

性能计数器只存在于 testbench，不会进入 FPGA 综合结果。

统计项目：

| 计数器 | 含义 |
|---|---|
| `perf_cycles` | halt 前有效统计周期 |
| `perf_instructions` | EX 完成的有效指令 |
| `perf_load_use_stalls` | load-use 停顿周期 |
| `perf_mdu_stall_cycles` | MDU 阻塞周期 |
| `perf_mdu_instructions` | 完成的 MDU 指令 |
| `perf_cond_predictions` | 条件分支预测次数 |
| `perf_cond_mispredictions` | 条件分支误预测次数 |
| `perf_predicted_taken_redirects` | ID taken 重定向次数 |
| `perf_flushes` | EX 恢复次数 |
| `perf_empty_ex_cycles` | EX 气泡周期 |

### 14.1 test7 性能分解

| 项目 | 数值 |
|---|---:|
| 周期 | 79 |
| 指令 | 68 |
| IPC | 0.8608 |
| CPI | 1.1618 |
| 200 MHz 吞吐率 | 172.15 MIPS |
| load-use stall | 3 |
| 控制流代价 | 6 |
| MDU stall | 0 |
| 其他/启动代价 | 2 |

Amdahl 理论上限：

| 假设完全消除 | 最大加速比 |
|---|---:|
| load-use | 1.0395 |
| 控制流代价 | 1.0822 |
| 预测 taken 的 1 周期气泡 | 1.0395 |
| 所有已跟踪代价 | 1.1286 |

所有已跟踪代价完全消除时：

```text
79 cycles -> 70 cycles
IPC -> 68 / 70 = 0.9714
200 MHz throughput -> 194.29 MIPS
```

### 14.2 test9 性能分解

| 项目 | 数值 |
|---|---:|
| 周期 | 361 |
| 指令 | 26 |
| IPC | 0.0720 |
| MDU 指令 | 10 |
| MDU stall | 330 |
| MDU stall 占比 | 91.41% |

因此：

- 优化 test7 应优先研究控制流重定向延迟和 load-use。
- 优化 test9 应优先减少 MDU 延迟或提高 MDU 吞吐率。
- 扩大 BHT 对当前 test7 的收益很低，因为条件分支已经 100% 正确。

## 15. Amdahl 定律如何使用

如果某类开销占总时间比例为 `f`，将这部分加速 `S` 倍，则总加速比：

```text
Speedup = 1 / ((1 - f) + f / S)
```

当某部分被无限加速，`S -> infinity`：

```text
Maximum speedup = 1 / (1 - f)
```

例如 test7 的 load-use 为 3/79：

```text
f = 3 / 79 = 0.0380
Maximum speedup = 1 / (1 - 0.0380) = 1.0395
```

这说明即使完全消除三个 load-use stall，总性能最多提升约 3.95%。优化前应先测量占比，避免在低占比模块上投入大量 RTL 和时序代价。

## 16. Python 参考模型

### 16.1 单周期功能模型

默认模式是单周期功能模型，适合：

- 检查指令语义。
- 查看寄存器和内存结果。
- 调试汇编。
- 与 RTL 最终状态对照。

```powershell
python riscv_single_cycle_sim.py --tdp test7_tdp.coe --max-cycles 300
python riscv_single_cycle_sim.py --tdp test9.coe --max-cycles 100 --dump-base 0x320 --dump-words 16
```

逐条指令 trace：

```powershell
python riscv_single_cycle_sim.py --tdp test7_tdp.coe --max-cycles 300 --trace
```

### 16.2 Python 五级流水线模型

```powershell
python riscv_single_cycle_sim.py --pipeline --tdp test7_tdp.coe --max-cycles 400
python riscv_single_cycle_sim.py --pipeline --tdp test9.coe --max-cycles 500 --trace-pipe
```

需要注意：

- Python `--pipeline` 模型包含五级流水线、前递、load-use、MDU stall 和 EX flush。
- 当前 Python `predict_taken()` 仍返回 false。
- 因此它没有完全同步最新 RTL 的 32 项 BHT 和 JAL taken 预测。
- Python 模型适合功能参考和流水线教学，最新 IPC、预测准确率和精确周期必须以 XSIM 自动 testbench 为准。

这一区别很重要：不要用 Python pipeline 的周期数覆盖 RTL 性能报告。

## 17. 重新创建 Vivado 工程

如果 `.xpr` 中存在本机缓存路径问题，可以在 Vivado Tcl Console 中执行：

```tcl
cd <repo-root>
source scripts/recreate_project.tcl
```

脚本会：

- 创建目标器件为 `xc7k325tffg900-2` 的工程。
- 加入当前有效 RTL。
- 加入 COE 文件。
- 加入自动 testbench。
- 加入 Clock Wizard 和 TDP BRAM XCI。
- 设置综合顶层和仿真顶层。
- 生成 IP output products。
- 更新编译顺序。

重建后建议检查：

```tcl
get_property top [current_fileset]
get_property top [get_filesets sim_1]
get_ips
```

预期：

```text
riscv_mcu_tdpram_top
riscv_cpu_auto_tb
clk_wiz_sys tdp_bram
```

## 18. 自动综合和实现

在 Vivado Tcl Shell 或 Windows 命令行运行：

```powershell
vivado -mode batch -source scripts/run_impl_current.tcl
```

脚本会：

1. 打开 `RISCV_FPGA.xpr`。
2. 使用 `synth_2`。
3. 使用 `impl_2`。
4. 设置 `Performance_Explore`。
5. 重置并运行综合。
6. 运行到 `route_design`。
7. 输出路由后 timing summary。

报告位置：

```text
RISCV_FPGA.runs/impl_2/riscv_mcu_tdpram_top_timing_summary_routed.rpt
RISCV_FPGA.runs/impl_2/riscv_mcu_tdpram_top_utilization_placed.rpt
```

当前路由结果：

| 指标 | 数值 |
|---|---:|
| Setup WNS | +0.124 ns |
| Hold worst slack | +0.113 ns |
| Slice LUT | 2957（1.45%） |
| Slice Register | 2030（0.50%） |
| Block RAM Tile | 32（7.19%） |
| DSP | 0 |

DSP 为 0 是因为当前 MDU 使用纯 RTL 移位加法/减法结构，而不是 DSP48 乘法器 IP。

## 19. 当前频率瓶颈

200 MHz 的最差 setup 路径：

```text
BHT two-bit counter
-> conditional prediction selection
-> predicted target / sequential address selection
-> instruction BRAM enable
```

主要特征：

- 数据路径约 4.154 ns。
- 逻辑延迟约 0.726 ns。
- 布线延迟约 3.428 ns。
- 布线占比约 82.5%。

这说明当前问题不只是比较器逻辑深度，还包括：

- BHT 状态到预测选择和目标地址路径较长。
- 指令 BRAM 分布范围和预测逻辑之间的布线较长。
- taken 预测必须在同一周期影响下一次 BRAM 请求。
- BRAM、寄存器堆、MDU 和控制逻辑的物理距离。

已经实验过将 forwarding selector 从 `ex_flush` 控制链中解耦。虽然原关键路径消失，但新关键路径转移到数据 BRAM 写入和预测取指路径，最终 WNS 下降到 +0.078 ns，因此没有保留该负优化。

后续频率优化必须同时考虑：

- EX 前递和比较路径。
- 数据地址到 BRAM 的写入路径。
- ID 预测到指令 BRAM 地址路径。
- 是否愿意增加流水级以及由此产生的控制流代价。

## 20. 如何添加新测试

推荐流程：

1. 编写 RV32I/RV32M 汇编。
2. 使用 RISC-V 工具链生成机器码。
3. 将 32 位 word 按十六进制写入 COE。
4. 在 Python 单周期模型中先检查功能。
5. 在 testbench 中增加预期寄存器和内存。
6. 运行 XSIM。
7. 检查性能计数器。
8. 运行综合和时序。

COE 示例：

```text
memory_initialization_radix=16;
memory_initialization_vector=
14000F93,
876540B7,
32108093;
```

自动 testbench 的 loader 会忽略不能按十六进制解析的 COE 头，只把合法 word 依次加载进 RAM。

若要增加 `TEST10`，可以仿照 `TEST9`：

```verilog
`ifdef TEST10
  localparam COE_FILE = "test10.coe";
  localparam HALT_PC = ...;
`endif
```

同时增加：

- `check_test10` task。
- 寄存器期望值。
- 内存期望值。
- 合理的 `MAX_CYCLES`。

## 21. 修改 RTL 后的回归清单

每次修改流水线、预测或 MDU 后至少执行：

```text
[ ] test7 行为仿真 PASS
[ ] test9 行为仿真 PASS
[ ] test7 指令数没有异常变化
[ ] test9 MDU 指令数正确
[ ] 没有新增 timeout
[ ] load-use stall 数变化符合预期
[ ] branch prediction 统计符合预期
[ ] 综合无 error
[ ] route 后 WNS >= 0
[ ] hold slack >= 0
[ ] 关键路径变化已记录并解释
[ ] git diff 不包含 Vivado 缓存和无关 IP 生成文件
```

优化不能只看仿真周期，也不能只看 WNS。推荐使用：

```text
应用性能 = IPC × 实际频率
```

例如某修改将周期从 79 降到 77，但最大频率从 200 MHz 降到 190 MHz：

```text
旧性能 = 68 / 79 × 200 = 172.15 MIPS
新性能 = 68 / 77 × 190 = 167.79 MIPS
```

虽然 IPC 变高，总性能反而下降。

## 22. 当前限制

- 没有 cache。
- 没有 MMU。
- 没有 CSR 完整实现。
- 没有异常和中断系统。
- 没有特权级。
- 没有 misaligned access trap。
- 条件分支 BHT 没有 tag，会发生 alias。
- 没有 BTB。
- JALR 不预测。
- 预测 taken 仍有 1 周期重定向气泡。
- 误预测恢复为慢恢复。
- MDU 一次只处理一条指令，并阻塞前端。
- 乘法目前也使用 32 次迭代，不是单周期或流水 DSP 乘法。
- Python pipeline 模型没有同步最新 BHT。
- 板级引脚约束尚未完成。
- 低地址空间存在 BRAM 地址截断 alias 的可能。

## 23. 建议的后续优化顺序

以 test7 为目标：

1. 研究 load-to-store 的晚前递，尝试消除两个 load/store 相邻 stall。
2. 研究 JALR 目标预测，但必须同时检查 ID 到 BRAM 的时序。
3. 研究预测重定向的零气泡取指结构。
4. 对 EX 分支前递和数据 RAM 地址路径进行联合流水化。
5. 使用更严格的频率约束重新做 PPA 比较。

以 test9 为目标：

1. 使用 DSP48 或 Booth/Wallace 结构降低乘法延迟。
2. 让乘法和除法采用不同延迟，而不是统一 32 次迭代。
3. 研究 radix-4 或更高基数除法。
4. 允许 MDU 与无关前端工作重叠，增加 scoreboard 或独立完成通路。
5. 保持 RISC-V 除零和溢出语义不变。

## 24. 阅读代码的推荐顺序

第一次接触工程时建议按以下顺序：

1. 阅读本 README 的第 3 至第 10 节。
2. 阅读 `riscv_inst_decode.v`。
3. 阅读 `riscv_imm_gen.v`。
4. 阅读 `riscv_alu.v` 和 `riscv_alu_decode.v`。
5. 阅读 `riscv_reg_file.v`。
6. 阅读 `riscv_cpu.v` 中的流水线寄存器定义。
7. 阅读前递和 load-use 检测。
8. 阅读分支预测和 EX 恢复。
9. 阅读主时序 always block。
10. 阅读 `riscv_mdu.v`。
11. 阅读 `riscv_cpu_auto_tb.v`。
12. 最后阅读 FPGA 顶层和时序报告。

这样可以先理解“指令如何流动”，再理解“为什么需要 stall/flush”，最后进入 FPGA 物理实现问题。

## 25. 提交问题时请附带的信息

为了让队友快速复现，请在 issue 或群聊中附带：

- 使用的 commit hash。
- Vivado 版本。
- 运行 test7 还是 test9。
- 完整 PASS/FAIL 输出。
- timeout 时的 PC。
- 修改前后的周期、IPC、stall 和 flush。
- 修改前后的 WNS。
- 新关键路径的 Source、Destination、Data Path Delay。
- 是否重新生成过 IP output products。
- 是否修改过 COE、XCI 或 XDC。

只说“结果不对”通常不足以判断是指令语义、流水线冒险、BRAM 对齐、仿真宏还是 Vivado 缓存问题。

---

当前主线目标是：在保持 test7/test9 功能正确的前提下，继续提高 `IPC × frequency`，并让每一次优化都能由自动仿真和路由后时序报告共同证明。
