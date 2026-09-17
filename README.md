# risc-mini NailongBranch2

这是一个用 SystemVerilog 实现的 32 位 RISC-V 教学 CPU/SoC。`NailongBranch2` 是团队当前完成度最高的历史分支，也是后续 CPU 开发的代码基线。

阶段提交与完成内容见 [工作日志](工作日志.md)。

> 历史基线：2026-09-10 曾依据提交 `73970f7` 的 205 个受版本控制文件完成静态审计，并用 Vivado Simulator 2024.2 独立编译、展开和仿真。那是当时的快照；当前状态以下文和实际工作区为准。代码、构建脚本和测试结果优先于旧设计报告与架构图。本项目尚不能视为通过完整 ISA 一致性、FreeRTOS、综合时序或板级验收的发布版本。

## 当前结论

- 当前 SoC 顶层是 [`rtl/soc.sv`](rtl/soc.sv)，当前 CPU 主线是 [`rtl/core/pipeline.sv`](rtl/core/pipeline.sv)。
- [`rtl/core/cpu.sv`](rtl/core/cpu.sv) 和 [`rtl/core/data_path.sv`](rtl/core/data_path.sv) 是未进入现有 SoC 与仿真文件表的旧实现，不应作为新功能入口。
- 主线核心是 RV32、单发射、顺序执行设计，包含取指/译码前端、EX、MEM、WB 四个逻辑处理阶段和三组级间寄存器。
- RTL 按设计意图覆盖 37 条整数/控制/访存指令及 RV32I 的 FENCE，并加入六条 Zicsr 指令、ECALL、EBREAK、MRET、非法/未对齐异常和一个实验性的机器定时器中断入口。
- UART、片上 ROM 和片上 RAM 已接入 SoC；GPIO 只有未使用的内部寄存器占位，定时器外设尚不存在。
- CPU 核心保留 `timer_int` 端口；当前 `soc` 将其明确固定为 0，避免悬空值进入控制逻辑。SoC 仍没有可用的定时器中断源。
- FreeRTOS 目录是混合版本、混合平台的参考移植素材：内核文件标记为 FreeRTOS Kernel V11.1.0，而配置、demo 与平台文件多为 V202212.00，并混有 QEMU `virt` 和另一套 SoC 的外设假设；尚未完成针对当前 SoC 的移植。

**阶段 1 验收边界：**`make phase1-behavior` 已串行通过 11 项项目回归、固定上游 RV32UI 40 项以及长序列、随机指令和 Trap 交叉测试；这证明的是当前 **M-only、固定一拍同步 ROM/RAM** 的行为基线。五级流水、可等待总线、BTB/BHT、两路 Cache、DDR、CoreMark、ACT4、PDS 时序与上板仍未完成。赛题目标和下一阶段入口见 [升级计划](升级计划.md)。

## 功能状态

| 子系统 | 当前状态 | 边界 |
| --- | --- | --- |
| RV32I 整数通路 | RTL 已实现，项目回归通过 | opcode、`funct3/funct7` 已严格检查；FENCE 仅在当前一拍顺序访存模型下等效空操作；尚未做 riscv-arch-test |
| Zicsr | M 模式第一版已验证 | 已实现 CSR 地址白名单、只读 CSR 写入检查；尚无 U/S 模式及完整 CSR 字段约束 |
| ECALL / EBREAK / MRET / 非法指令 | 第一版精确 Trap 已验证 | 支持 M 模式 ECALL cause 11、EBREAK cause 3、非法指令 cause 2 和 MRET |
| 地址未对齐异常 | 第一版已验证 | 支持 RV32I 控制流目标 cause 0、Load cause 4、Store cause 6；`mtval` 保存故障值 |
| 性能计数器 | RTL 与定向仿真已验证 | 64 位 cycle、instret 和自定义 stall；尚未综合测资源或时序 |
| 机器定时器中断 | 核心第一版精确提交与请求保持已验证，SoC 暂时禁用 | 要求 `mstatus.MIE` 与 `mie.MTIE`；具有 `mip.MTIP` pending，但 SoC 仍没有同步器和 CLINT/mtime |
| 分支与冒险 | RTL 已实现 | Branch/JAL 静态预测跳转，JALR 在 EX 纠正；有 EX/MEM/WB 前递和 load-use 停顿 |
| UART | RTL 与 hello 软件已接入 | 尚无自检 UART testbench，也没有本次板级串口记录 |
| ROM / RAM | RTL 已实现 | 物理容量各 4 KiB；`.mem` 生成已与 ROM 对齐，但链接脚本仍声明 128 KiB ROM/RAM |
| GPIO | 未实现 | `PORTA` 仅声明，未做地址映射、读写或顶层引脚 |
| FreeRTOS | 未集成 | 目录内容仍面向 QEMU virt，不能直接在本 SoC 启动 |
| FPGA 工程 | 只有 RTL 和旧 Xilinx XDC | 仓库没有目标盘古100Pro+的 PDS 工程、约束、综合/实现报告或 bitstream；旧 XDC 不能直接用于 PG2L100H |

## 当前硬件结构

```text
                         +---------------- pipeline ----------------+
同步指令 ROM -> PC/译码/寄存器读取/前递 -> [前端/EX] -> EX/CSR
                                                   -> [EX/MEM]
同步数据 RAM/UART <-> LMB 字节通道适配 <---------- MEM
                                                   -> [MEM/WB]
                                                   -> WB -> GPR
                         +------------------------------------------+
```

三个级间寄存器位于：

- 前端到 EX：`pipeline.sv` 的前端/EX 寄存器；
- EX 到 MEM：ALU、CSR、目的寄存器和写回控制寄存器；
- MEM 到 WB：内存数据、ALU/CSR 结果和目的寄存器。

### 活跃模块

| 模块 | 作用 |
| --- | --- |
| `rtl/soc.sv` | SoC 顶层，连接复位、总线、UART 和 `pipeline` |
| `rtl/core/pipeline.sv` | 当前 CPU 顶层，组织控制、数据通路和三组级间寄存器 |
| `rtl/core/pc_reg.sv` | PC、静态跳转预测、停顿与重定向 |
| `rtl/core/decoder.sv` | RV32I 主 opcode、Zicsr、ECALL、EBREAK、MRET 译码 |
| `rtl/core/ctrl.sv` | load-use 停顿、分支纠正、Trap/MRET 重定向 |
| `rtl/core/reg_file.sv` | 32 × 32 位、2 读 1 写寄存器堆 |
| `rtl/core/forward.sv` | EX、MEM、WB 到前端操作数的旁路 |
| `rtl/core/ex.sv` | 立即数、ALU 操作数和 CSR 读改写计算 |
| `rtl/core/alu.sv` | 整数运算、比较和分支条件 |
| `rtl/core/csr_file.sv` | M 模式 CSR 子集和 Trap/MRET 状态更新 |
| `rtl/core/lmb.sv` | 数据地址、字节写使能、Load 对齐与扩展 |
| `rtl/core/wb.sv` | ALU、内存、PC+4、CSR 四路写回选择 |
| `rtl/peripherals/bus.sv` | ROM、RAM、I/O 地址译码和读数据返回 |
| `rtl/peripherals/io.sv` | UART MMIO 寄存器与收发模块 |

### 历史实现

`rtl/core/cpu.sv` 和 `rtl/core/data_path.sv` 保留了早期非当前主线的数据通路。它们不在 `sim/Makefile` 的 RTL 列表中，`soc.sv` 也没有实例化它们。后续修改前应先确认目标属于 `pipeline.sv` 主线，避免在 legacy 代码上开发。

## 指令与特权功能

### RV32I 设计覆盖

- R 型：ADD、SUB、SLL、SLT、SLTU、XOR、SRL、SRA、OR、AND
- I 型：ADDI、SLLI、SLTI、SLTIU、XORI、SRLI、SRAI、ORI、ANDI
- 分支：BEQ、BNE、BLT、BGE、BLTU、BGEU
- Load：LB、LH、LW、LBU、LHU
- Store：SB、SH、SW
- 跳转与高位立即数：JAL、JALR、LUI、AUIPC
- 存储顺序：FENCE（当前无未完成请求的顺序单核中不额外等待）

上述清单表示 RTL 的译码和数据通路意图，不等同于通过 RV32I compliance。译码器现严格检查支持指令的 opcode、`funct3` 和 `funct7`；未知或不支持的编码进入同步非法指令异常（cause 2），不会再静默表现为 NOP 或被别名为已有运算。`EBREAK` 单独产生 breakpoint cause 3。FENCE 的合法编码会退休且无寄存器/存储器副作用；引入 Cache、DMA 或可等待总线时必须重新实现排序等待。独立扩展 Zifencei 的 FENCE.I 尚未实现，现产生非法指令异常。

当前核心会检查非对齐访问：RV32I 控制流目标必须按 4 字节对齐，LH/SH 按 2 字节对齐，LW/SW 按 4 字节对齐；违例分别产生 cause 0、4、6，并由提交门控阻止故障指令产生副作用。JALR 先按规范清零目标 bit 0，再检查 bit 1。`mtval` 记录故障目标或访存地址；`mtvec` 基址和 `mepc` 已对齐，但尚未检测指向未映射/不可执行存储区域的目标。数据通路是小端序。

### Zicsr 和 CSR

已接入 CSRRW、CSRRS、CSRRC、CSRRWI、CSRRSI、CSRRCI。当前 CSR 文件如下：

| CSR | 地址 | 当前行为 |
| --- | ---: | --- |
| `mstatus` | `0x300` | 仅 MIE bit 3 和 MPIE bit 7 可写；MPP bits 12:11 固定为 M 模式 `11`，其余未实现位读 0；Trap/MRET 更新 MIE/MPIE |
| `mie` | `0x304` | 仅 `MTIE` bit 7 可写并参与 Timer 门控，其他未实现中断使能位读 0 |
| `mtvec` | `0x305` | BASE 为 4 字节对齐地址；MODE=0 Direct 时所有 Trap 到 BASE，MODE=1 Vectored 时异步中断到 BASE+4×cause、同步异常仍到 BASE；写入保留 MODE=2/3 会读回 MODE=0 |
| `mscratch` | `0x340` | 可读写 |
| `mepc` | `0x341` | 软件写入和 Trap 保存时清零 bits 1:0；MRET 从对齐地址返回（本核 IALIGN=32） |
| `mcause` | `0x342` | 可读写；当前生成指令地址未对齐 0、非法指令 2、EBREAK 3、Load 未对齐 4、Store 未对齐 6、ECALL 11 和机器定时器中断 `0x80000007` |
| `mtval` | `0x343` | 可读写；Trap 时保存非法编码、未对齐目标或访存地址；EBREAK/ECALL/Timer 写 0 |
| `mip` | `0x344` | `MTIP` bit 7 只读反映已锁存 Timer 请求；CSR 写入会产生非法指令异常；请求真正被接收后由硬件清除 |
| `mhartid` | `0xF14` | 固定读 0 |
| `cycle/cycleh`、`instret/instreth` | `0xC00/0xC80`、`0xC02/0xC82` | 64 位计数的只读低/高半字 |
| `mcycle/mcycleh`、`minstret/minstreth` | `0xB00/0xB80`、`0xB02/0xB82` | 同一计数器的机器态可写别名 |
| 自定义 `stall_cycles/stall_cyclesh` | `0xCC0/0xCC1` | 有效暂停周期的只读低/高半字 |

其他未列出的 CSR 地址仍产生非法指令异常（cause 2）。`mhartid`、`mip`、`cycle/instret` 和自定义 stall CSR 只允许纯读取：`CSRRS/CSRRC` 的 `rs1=x0` 或立即数形式的 `uimm=0` 不尝试写入，因此合法。`mtvec/mstatus/mie/mepc` 已约束当前实现的字段；`time`、除 `mip.MTIP` 外的其他 `mip` 位及 U/S 特权模式尚未实现。MPP 虽读回 M 模式，但没有 U/S 模式切换机制。

### 控制流和冒险

- 条件分支和 JAL 在前端静态预测为跳转；JALR 预测为顺序执行。
- 条件分支预测失败和 JALR 目标在 EX 阶段通过 `pc_mis/target_pc` 纠正。
- 数据前递优先级为 EX > MEM > WB，覆盖 ALU、Load、PC+4 和 CSR 写回源。
- load-use 冒险触发一拍停顿并向 EX 插入 bubble。
- Trap、MRET 和分支纠正共用 PC 重定向通路。PC 重定向现高于普通 `stall`；定向测试覆盖了 load-use 停顿与 Timer Trap 同周期发生的情况。
- EX、MEM、WB 现有显式 `valid` 状态；Trap 可 kill 当前 EX 指令，Store、CSR 和通用寄存器写入均受提交条件约束。

## 存储器与 MMIO

核心使用分离的指令和数据接口。当前 SoC 的 ROM/RAM 都是上升沿同步读，没有 ready/valid、wait-state 或总线错误响应；替换存储器或接入外部总线时必须保持一拍返回关系，或同时重构流水控制。

### 地址映射

| 软件基址 | 区域 | RTL 实际资源 | 说明 |
| ---: | --- | ---: | --- |
| `0x0000_0000` | 程序 ROM / 数据只读窗口 | 4 KiB | `flash[0:1023]`，指令和数据各一个同步读端口 |
| `0x2000_0000` | 数据 RAM | 4 KiB | `ram[0:1023]`，支持 4 位字节写使能 |
| `0x4000_0000` | UART MMIO | 低 8 位地址译码 | 当前只有 UART 寄存器有实际行为 |

总线只用 `mem_addr[31:28]` 选择区域，ROM/RAM 内部只用 `addr[11:2]`。因此同一高 4 位区域中的高地址会别名到这 4 KiB 物理存储，不能把整个 `0x0...` 或 `0x2...` 区域当作真实容量。

### UART 寄存器

| 地址 | 名称 | 行为 |
| ---: | --- | --- |
| `0x4000_0000` | `USR` | bit 5 `RXNE`，bit 6 `TC` |
| `0x4000_0004` | `UDR` | 写低 8 位启动发送；读低 8 位取得接收数据 |
| `0x4000_0008` | `UBRR` | 低 16 位为分频值，计算式为 `f_clk / baud - 1` |
| `0x4000_000C` | `UCR1` | 当前仅可存取，未参与收发控制 |

UART 为 8N1，无 FIFO。`rxd` 在 `uart_rx` 内经过两级同步。当前 `RXNE` 清除条件没有受 I/O 片选或独立读使能约束：任何未写、且地址低 8 位为 `0x04` 的数据访问都可能清除它，并不只限于读取 UART `UDR`。此外，预留的 `IO_BASE_PORT0 = 0x04` 与 `UDR` 偏移重叠；接入 GPIO 前必须先重新规划地址译码。

### 当前容量不一致

| 项目 | 当前值 |
| --- | ---: |
| RTL 程序 ROM | 4 KiB |
| RTL 数据 RAM | 4 KiB |
| `src/Makefile` 生成的 `.mem` | 4 KiB / 1024 个 32 位字 |
| `src/sample.ld` 声明的 ROM | 128 KiB |
| `src/sample.ld` 声明的 RAM | 128 KiB |
| 未被当前构建选用的 `src/link.ld` ROM | 512 KiB |
| 未被当前构建选用的 `src/link.ld` RAM | 1 MiB |
| FreeRTOS RV32 heap 配置 | 80 KiB |

当前 hello 的有效内容能装入 4 KiB ROM；`src/Makefile` 会将 `.mem` 补零到与 `flash` 一致的 1024 个字，并在二进制超过 4 KiB 时立即失败，避免静默截断。链接脚本仍声明 128 KiB ROM/RAM，后续扩大物理存储器或定稿地址空间时还需要统一。

## 时钟、复位与 FPGA 约束

- [`rtl/phosphor_zynq.xdc`](rtl/phosphor_zynq.xdc) 是旧 Xilinx 板卡约束，声明 20 ns 周期，即 50 MHz；它不描述目标盘古100Pro+的时钟或管脚。
- 顶层端口为 `clk`、低有效 `rst_n`、`rxd`、`txd`。
- 旧 XDC 中的引脚为 `clk/U18`、`rst_n/N16`、`rxd/T19`、`txd/J15`，均使用 LVCMOS33；这些编号不能套用于 PG2L100H。
- `reset_sync` 对外部复位异步置位、同步两拍释放，并生成核心内部高有效 `rst`。
- PC 和级间寄存器使用同步高有效复位，CSR 文件使用异步高有效复位，GPR 没有复位。
- PC 复位为 `0xFFFF_FFFC`，组合的下一取指地址因此从 `0x0000_0000` 开始。

仓库没有目标板 PDS 工程或实现报告。现有仿真 SoC 顶层为 `soc`；创建盘古100Pro+工程前，需按随板原理图和例程核对 `PG2L100H-6FBG676`、时钟、复位及引脚，并为 DDR/外设集成确认最终顶层与 PDS 约束，不能直接导入旧 XDC。

## 软件与镜像构建

推荐在 Linux 或仓库提供的 Dev Container 中构建。容器安装：

- Icarus Verilog (`iverilog`、`vvp`)
- GNU Make
- `riscv64-unknown-elf` 工具链
- picolibc
- Universal Ctags

默认应用是 `src/hello`，目标架构为 `rv32i_zicsr`、ABI 为 `ilp32`。工具链路径和架构选项位于 [`src/config.mk`](src/config.mk)。

```bash
# 当 .bin 不存在时构建整套 hello 产物，然后运行当前 testbench
make

# 按时间戳更新 .disasm/.mem/.coe 等软件产物并运行仿真
make all

# 强制重建全部软件与仿真产物
make clean && make all

# 清理软件和 Icarus 仿真产物
make clean
```

根 Makefile 的默认目标只跟踪 `src/risc-mini.bin`。在全新 checkout 或 `make clean` 后，`.bin` 不存在，默认 `make` 会调用 `make -C src all` 并生成整套软件产物；但 `.bin` 一旦存在，根 Makefile 就不会根据 C 源码、链接脚本或其他镜像的变化重新进入 `src`。日常软件开发应使用 `make all`，需要完全重建时使用 `make clean && make all`。如果只删除 `.mem` 而保留 `.bin`，默认 `make` 会在 `sim` 阶段因没有 `.mem` 生成规则而失败。

成功构建后会生成：

- `src/hello/hello.elf`
- `src/risc-mini.disasm`
- `src/risc-mini.bin`
- `src/risc-mini.mem`
- `src/risc-mini.coe`

`src/risc-mini.mem` 是当前 RTL/仿真的初始化文件，`.coe` 供后续 Vivado BRAM 初始化使用。`src/config.mk` 实际选择 `src/sample.ld` 和工具链自带的 `picolibc.ld`；仓库内另一份 `src/link.ld` 未被当前构建选用，而且使用了脚本内未定义的 `__stack_size`，不能直接视为可替换的完整链接脚本。

当前构建规则固定使用 Linux `/usr/bin` 下的 `riscv64-unknown-elf` 工具链及 picolibc include/specs，并要求工具链具备 RV32I/ILP32 multilib；镜像规则还依赖 `cat`、`head`、`hexdump` 和 `sed`。因此 Windows 原生命令行不是现成的受支持构建环境，优先使用仓库 Dev Container。

### 选择 testbench

`sim/Makefile` 中的变量名保留了原有拼写 `TB_MOUDLE`，当前默认值是 `tb_soc.sv`。Makefile 会根据文件名显式选择同名仿真顶层；切换 testbench 时建议用 `-B` 强制重建：

```bash
make -B -C sim TB_MOUDLE=tb_pipeline.sv
make -B -C sim TB_MOUDLE=tb_dhazards.sv
make -B -C sim TB_MOUDLE=tb_control.sv
make -B -C sim TB_MOUDLE=tb_csr.sv
make -B -C sim TB_MOUDLE=tb_interrupt.sv
make -B -C sim TB_MOUDLE=tb_perf_counters.sv
make -B -C sim TB_MOUDLE=tb_mtvec.sv
make -B -C sim TB_MOUDLE=tb_csr_fields.sv
make -B -C sim TB_MOUDLE=tb_halfword.sv
make -B -C sim TB_MOUDLE=tb_fence.sv
make -B -C sim TB_MOUDLE=tb_soc.sv
```

日常回归使用以下入口：

```bash
# 指令、冒险、控制流、CSR 和 SoC smoke test
make regression

# 在上述测试之外加入异常/中断、性能计数器、CSR 字段及半字访存测试
make regression-all

# 上游 RV32UI 40 项，以及本地长序列和 4 种子随机指令混合
make isa-smoke
make trap-mix
make phase1-behavior

# 只在调试单项测试时生成波形
make -B -C sim TB_MOUDLE=tb_control.sv DUMP_WAVES=1
```

每个 CPU testbench 只有在全部检查通过后才输出唯一的 `[TB PASS]` 标记；失败会累计并调用 `$fatal`。回归脚本还会检查进程状态、失败文本、超时、完成标记以及 SoC 的 `Hello, World!` UART 输出。标准回归保存到 `sim/regression.log`，含中断和计数器测试的完整回归保存到 `sim/regression-all.log`，便于宿主机直接检查。

`phase1-behavior` 串行执行 `regression-all → isa-smoke → trap-mix`，任一项失败即停止。`isa-smoke` 首次运行需容器能访问 GitHub，脚本获取固定提交 `riscv-tests@2ebecad997fa58cd9e5724340ba75aa4b59bd1d0` 到临时目录，并用容器中的 RISC-V GCC/Icarus 编译运行。已有该提交的本地检出时，可设置 `RISCV_TESTS_DIR=/path/to/riscv-tests` 避免网络获取；脚本会核对提交哈希。上游测试源码不复制到本仓库。
同一命令还运行本地固定种子长序列和 4 组可复现的随机指令混合；长序列使用 `+MAX_CYCLES` 扩大单项测试的超时上限，不会改变上游 40 项的默认 8000 周期保护。

## FreeRTOS 目录的真实状态

[`src/FreeRTOS`](src/FreeRTOS) 混合了 FreeRTOS Kernel V11.1.0 内核、V202212.00 配置/demo、RISC-V portable 层、QEMU virt 平台文件和另一套 SoC 示例。它目前是参考移植素材，不是已适配应用：

- `src/Makefile` 默认仍选择 `hello`；
- FreeRTOS 配置使用 25 MHz，而 XDC 和 `mini_libc` 使用 50 MHz；
- 配置期望 CLINT `mtime/mtimecmp` 位于 `0x0200_0000` 区域，当前 SoC 没有 CLINT；
- 示例代码使用 `0x1000_0000` 的 NS16550，另一些 UART 宏使用 `0x4000_4000`，当前 UART 实际位于 `0x4000_0000` 且寄存器布局不同；
- `main.c` 默认把 `mtvec` 配为 vectored 模式，核心现支持该入口计算；但现有 FreeRTOS 镜像、向量表处理程序和实际中断源尚未做端到端验证；
- 80 KiB heap 和 128 KiB 链接 RAM 都超过实际 4 KiB RAM；
- SoC 当前将 `timer_int` 固定为 0；核心已有 `mie.MTIE`、`mip.MTIP` 和精确提交，但仍没有板级中断源、CDC 同步与 CLINT/mtime。
- FreeRTOS Makefile 没有编译仓内 `start.S`，启动和 `.data/.bss` 初始化依赖 picolibc CRT；它还会无条件编译 full-demo 文件集合，不能把默认 blinky 选择等同于精简镜像。
- FreeRTOS 应用没有调用当前 `mini_libc` 的 `uart_init`；UART 分频寄存器复位为 0，即使 stdout 映射改对，也仍需显式设置板级波特率。

只有在统一平台地址、时钟、启动代码、链接布局、Trap ABI 和计时器硬件，并通过上下文切换与 tick 中断测试后，才能把 FreeRTOS 状态改为“支持”。

## 验证资产与本次结果

### 已有 testbench

| 文件 | 设计目标 |
| --- | --- |
| `sim/tb_pipeline.sv` | 指令类别、Load/Store、跳转与分支预测 |
| `sim/tb_dhazards.sv` | EX/MEM/WB 前递、load-use、Store、栈保存、memcpy |
| `sim/tb_control.sv` | 条件分支预测/纠正、JAL、JALR 与 Flush |
| `sim/tb_csr.sv` | CSR 读写、立即数形式和 CSR 数据前递 |
| `sim/tb_interrupt.sv` | ECALL、EBREAK、MRET、非法/未对齐异常、精确提交、mcause/mepc/mtval 和外部 timer 脉冲 |
| `sim/tb_perf_counters.sv` | cycle/instret/stall 计数、CSR 别名、机器态高低半字写入及 64 位进位 |
| `sim/tb_mtvec.sv` | Direct/Vectored 入口、同步异常与 Timer 向量区分、保留 MODE 的 WARL 读回 |
| `sim/tb_csr_fields.sv` | M-only 的 mstatus/mie 字段、mepc 对齐及 Trap/MRET 状态恢复 |
| `sim/tb_halfword.sv` | 同步 RAM 下 LH/LHU/SH 高低半字、符号扩展、写掩码与未对齐无副作用 |
| `sim/tb_isa_smoke.sv` | 上游 RV32UI、本地长序列及随机指令混合的同步 ROM/RAM 适配、结果码和宿主机 RAM 参考值检测 |
| `sim/isa_smoke/gen_random_stream.sh` | 从固定种子生成运算指令序列及独立的 32 位宿主机预期结果 |
| `sim/tb_soc.sv` | 复位后运行当前 ROM 镜像的定时 smoke test |

### 2026-09-10 审计结果

使用 Vivado Simulator 2024.2 对仓库全部 27 个 SystemVerilog 文件执行编译，并展开六个 testbench 顶层：

- `xvlog` 完成解析，但在 `pipeline.sv` 报告 22 处“使用时隐式声明、随后再次声明”的警告；这些信号应移到首次使用之前显式声明。
- 六个 testbench 均能完成静态展开；展开同时确认多处 `timer_int` 未连接，`soc` 顶层也存在该警告。
- `tb_pipeline`、`tb_dhazards`、`tb_control`、`tb_csr` 和 `tb_interrupt` 的自检均报告功能失败或 X 值，不能把当前提交标记为回归通过。
- `tb_soc` 能运行到 `$finish`，但隔离运行目录下的 Xilinx 仿真分支找不到写死为当前目录的 `risc-mini.mem`，且该 testbench 没有 UART/程序结果断言，因此不构成功能通过。
- 当前 testbench 主要通过打印 `[PASS]/[FAIL]` 判断；部分任务在打印失败后仍无条件打印 `[PASS]`，多数失败不会令仿真返回非零状态。自动化脚本不能只看进程退出码。

仓库 Makefile 的目标仿真器是 Icarus Verilog。本次 Windows 环境没有 `iverilog` 和 RISC-V 交叉工具链，Docker 引擎也未运行，因此尚未补跑仓库原生 Make 回归。Vivado 结果不能替代 Icarus 结果，但已经足以说明当前基线不是绿色回归状态。

### 2026-09-15 仿真基线框架更新

- 六个 testbench 的模块名已与文件名统一，Icarus 编译时显式指定唯一顶层。
- 非中断测试和 SoC 将 `timer_int` 明确固定为 0；SoC 的 `rxd` 固定为空闲高电平。
- testbench 已加入统一的错误计数、最终通过标记和失败退出；默认关闭波形转储。
- Vivado Simulator 2024.2 已无警告编译全部 SystemVerilog，并成功静态展开六个 testbench。
- 初次 Vivado 功能预检中，`tb_control` 与 Icarus 的 JALR 结果不一致；该次 `tb_interrupt` 还因组合取指模型形成零延迟反馈而未正常完成。同步取指修复后，`tb_interrupt` 已在 Icarus 和 Vivado Simulator 2024.2 中一致通过；其余完整功能一致性仍需后续复核。
- `tb_interrupt` 改为与 `flash.sv` 一致的同步取指，并加入阶段标记和周期看门狗后，Docker/Icarus 完整回归于 2026-09-15 得到 `6 passed, 0 failed`：控制流、数据冒险、基本指令、CSR、SoC hello、ECALL/MRET 和现有 Timer 用例全部通过。

### 2026-09-15 阶段 1：Timer 门控与重定向优先级

- `tb_interrupt` 增加三种组合测试：`mstatus.MIE=0`、`MIE=1/MTIE=0` 和 `MIE=1/MTIE=1`。
- 修复前第二种组合会错误进入 Timer Trap；修复后只有 `mstatus.MIE` 与 `mie.MTIE` 同时为 1 才接收中断。
- 新增 Timer Trap 与 load-use `stall` 同周期测试。修复前 CSR 会记录 Trap，但 PC 因暂停而丢失 `mtvec` 跳转；现已将重定向优先级提高到 `stall` 之上。
- Docker/Icarus 完整回归保持 `6 passed, 0 failed`，同一中断用例也通过 Vivado Simulator 2024.2 独立编译、展开和行为仿真。
- `.vscode/settings.json` 明确让 Icarus lint 从工作区根目录运行，避免把 `rtl/core` 等库路径误解析成 `rtl/rtl/core` 后产生 Unknown module 假报错。
- 上述结果只验证了中断门控和 PC 重定向优先级，尚不代表精确中断、挂起位或板级定时器已经完成。

### 2026-09-16 阶段 1：`valid/kill/commit` 第一版

- 在 EX、MEM、WB 三个处理级加入显式有效位，bubble 和冲刷不再只依靠控制信号清零表示。
- Timer Trap 在 EX 接受时 kill 当前指令：若 `mepc` 保存该指令地址，当前执行不会提交，MRET 后由重执行完成一次提交。
- Store 写使能、CSR 写使能和通用寄存器写回均加入提交门控；寄存器堆不再在每个时钟沿无条件写入。
- 新测试让 Timer 与 `sw` 的 EX 周期重合。修复前同一 Store 写两次，修复后只在 MRET 返回后写一次。
- Docker/Icarus 完整回归为 `6 passed, 0 failed`；中断用例也通过 Vivado Simulator 2024.2，结束于 1305 ns。
- 三指令边界测试进一步证明：Trap 前的老指令完成，当前 Store 被 kill 后只在 MRET 后提交一次，年轻 Store 在进入 Handler 前没有副作用；Icarus 与 Vivado Simulator 均通过，Vivado 仿真结束于 1785 ns。
- 这仍是精确 Trap 的第一版：尚需实现地址未对齐和中断挂起行为。

### 2026-09-16 阶段 1：非法指令异常

- 译码器默认判定编码非法，只对已支持 RV32I/Zicsr 编码显式置 `inst_valid`，并严格检查 R/I 移位、Branch、Load、Store、JALR 和 SYSTEM 子编码。
- `valid_ex` 表示“流水级中存在一条真实指令”，`inst_valid` 表示“该指令编码受支持”；非法指令仍进入 EX，并产生同步异常 cause 2，而不是变成 bubble。
- 同步非法指令异常优先于异步 Timer 中断，并复用现有 `trap/kill/commit` 路径，保证故障指令和年轻指令不产生寄存器、CSR 或 Store 副作用。
- `tb_interrupt` 验证一次 Trap、`mcause=2`、精确 `mepc` 和处理后继续执行；Docker/Icarus 完整回归为 `6 passed, 0 failed`，Vivado Simulator 2024.2 同项通过并结束于 2155 ns。
- 完整回归同时暴露并修复了 `tb_pipeline` 的同步指令存储器初始化顺序：现在先填充存储器，再保持复位两个周期，避免把未知输出误当成真实取指。
- 该次验证的边界：CSR 地址/权限尚未参与非法检查，EBREAK 尚无 cause 3；这些功能已在后续小节补齐。

### 2026-09-16 阶段 1：地址未对齐异常

- EX 阶段使用最终有效地址检查 LH/LHU、LW、SH 和 SW 的自然对齐；故障 Load 不写回目标寄存器，故障 Store 不拉高任何内存写使能。
- 对 JAL、实际采用的 Branch 和 JALR 检查真实目标地址；RV32I 不含压缩指令，因此目标必须 4 字节对齐。未采用的条件分支不检查其未使用目标。
- 异常优先级现为同步地址异常/非法指令/ECALL 高于异步 Timer；cause 分别为指令地址 0、Load 4、Store 6。
- `tb_interrupt` 验证未对齐 LW 保留寄存器哨兵值、未对齐 SW 无写使能、未对齐 JAL 精确返回。Docker/Icarus 完整回归为 `6 passed, 0 failed`，Vivado Simulator 2024.2 同项通过并结束于 3205 ns。
- 该次验证的边界：当时尚未实现 `mtval`，也未检查 MRET 的 `mepc` 或 Trap 的 `mtvec` 配置错误；后续已补 JALR、taken/not-taken Branch 的交叉用例，LH/SH 与 `mtvec/mepc` 配置边界仍待验证。

### 2026-09-16 阶段 1：Timer 请求保持

- 新增 `mip.MTIP` pending：同步的一拍 `timer_int` 即使发生在 MIE/MTIE 关闭期间也会被锁存，开放后在最早的精确指令边界接收。
- Timer 只有在赢得异常仲裁时才产生 `timer_irq_taken` 并清 pending；若与 ECALL 等同步异常同周期，先处理同步异常，Timer 保持到 MRET 后再处理。
- 已使能且没有更高优先级异常时，原始 `timer_int` 仍可当拍被接收，不额外增加正常中断延迟。
- `tb_interrupt` 覆盖 pending 的置位、跨 MIE/MTIE 屏蔽保持、接收后清除及 ECALL/Timer 冲突。Docker/Icarus 完整回归为 `6 passed, 0 failed`，Vivado Simulator 2024.2 同项通过并结束于 3735 ns。
- 当前接口约定 `timer_int` 与 CPU `clk` 同步且表示事件脉冲。未来接入异步引脚或标准电平型 `mtime/mtimecmp` 时，必须增加 CDC 同步并重新确定中断源清除/确认协议。

### 2026-09-16 阶段 1：CSR 地址和只读属性

- 译码阶段只接受当前 CSR 文件真实实现的地址；未实现地址访问产生精确非法指令异常 cause 2，不再静默读 0。
- `mip` 与 `mhartid` 只读；区分 CSRRW/CSRRWI 的写入意图，以及 CSRRS/CSRRC/立即数形式零源操作数的纯读取。非法写入不修改 CSR，也不向通用寄存器写回。
- `tb_interrupt` 覆盖未实现地址、两个只读 CSR 的非法写入、合法纯读取和处理程序返回。Docker/Icarus 完整回归 `6 passed, 0 failed`；Vivado Simulator 2024.2 同项通过（4455 ns）。
- 当前核心只有 M 模式；本项不代表已实现 U/S 特权级检查或所有 CSR 的字段级 WARL 规则。

### 2026-09-16 阶段 1：性能计数器

- `cycle`/`cycleh`（`0xC00/0xC80`）和 `instret`/`instreth`（`0xC02/0xC82`）提供 64 位计数的只读低/高半字；机器态 `mcycle`/`mcycleh`、`minstret`/`minstreth` 是同一计数的可写别名。尚未实现 `time`，因此不是完整 Zicntr。
- 自定义只读 CSR `0xCC0/0xCC1` 提供 64 位 `stall_cycles`：仅当 `stall=1` 且 PC 未被 Trap/MRET/分支纠正重定向时计数。它是当前流水线的有效暂停周期，不等同于未来 Cache miss 计数。
- `instret` 在 WB 有效指令退休时递增，包含 Store、Branch、`jal x0` 等不写通用寄存器的指令；被异常/中断取消的指令和 bubble 不计数。复位期间三个计数器均清零。
- `tb_perf_counters` 覆盖 load-use 停顿、软件可读 CSR、机器态高低半字写入和 64 位进位；`tb_interrupt` 同时核对多次 Trap 及 Trap/stall 重合后的累计值。Docker/Icarus 完整回归 `7 passed, 0 failed`；Vivado Simulator 2024.2 两项定向测试通过（计数器 1 μs、中断 4455 ns）。
- 这些计数可用于测量代码段的周期差、退休指令差和当前已实现的 load-use 暂停差；以后引入 Cache/握手后应新增事件分类，不能把总周期差全部归因于某一模块。尚未做 PDS 综合或板级性能测量。

### 2026-09-16 阶段 1：EBREAK 与 mtval

- 精确识别 `EBREAK`（`0x00100073`）并产生 breakpoint cause 3；故障指令被 kill，不会退休，Handler 可修改 `mepc` 后通过 MRET 继续执行。
- 新增可读写 `mtval`（`0x343`）。发生 Trap 时硬件优先覆盖：非法指令存原始 32 位编码；未对齐指令目标存实际跳转目标；未对齐 Load/Store 存实际访存地址；EBREAK、ECALL、Timer 存 0。MRET 本身不改写 `mtval`。
- `tb_interrupt` 验证各类故障值、软件写入与读回、EBREAK 的 cause/mepc/返回，以及 JAL/JALR/taken Branch 的未对齐目标；未采用的分支不误报。Docker/Icarus 完整回归 `7 passed, 0 failed`；Vivado Simulator 2024.2 的 `tb_interrupt`（5555 ns）和 `tb_perf_counters`（1 μs）均通过。
- 该阶段尚未实现 `mtvec` Direct/Vectored 与 CSR 字段级 WARL 规则；后续小节已补 `mtvec`，其他 CSR 字段仍待完善。以上是行为仿真结果，不代表 PDS 综合或上板已验证。

### 2026-09-16 阶段 1：`mtvec` Direct/Vectored

- `mtvec` 拆为 BASE 和 MODE。Direct（MODE=0）所有 Trap 进入 BASE；Vectored（MODE=1）同步异常仍进入 BASE，异步中断进入 `BASE + 4 × mcause 编号`。例如 `mtvec=0x41` 时，ECALL 到 `0x40`，Timer cause 7 到 `0x5c`，不会把 `0x41` 当取指地址。
- 本实现仅支持 MODE 0/1；软件写入保留编码 2/3 时按 WARL 读回 0，BASE 保持 4 字节对齐。当前只有 Timer 一种中断源；向量槽可放跳转到共用 Handler 的指令，不代表已实现多来源仲裁或软件中断处理框架。
- `tb_mtvec` 验证 Direct ECALL、Vectored ECALL/Timer、向量槽执行与 MRET，以及保留 MODE 读回。Docker/Icarus 完整回归 `8 passed, 0 failed`；Vivado Simulator 2024.2 独立编译、展开并通过该定向用例（830 ns）。尚未做 PDS 综合与上板测试。

### 2026-09-16 阶段 1：M-only CSR 字段与 MRET 返回

- `mstatus` 只保留 MIE/MPIE，MPP 固定为唯一支持的 M 模式；`mie` 只保留 MTIE。软件写入其他位会读回 0，不会制造并不存在的特权级或中断使能。
- 本核仅支持 32 位对齐取指（IALIGN=32），因此 `mepc[1:0]` 在软件写入或 Trap 保存时清零；MRET 使用此对齐地址。例如软件写 `mepc=0x83`，读回及返回目标是 `0x80`。这不表示已检测目标存储器是否存在。
- `tb_csr_fields` 覆盖全 1 字段写入、读回、对齐返回、ECALL 时 MIE/MPIE 转换、Handler 修正 `mepc` 后再次 MRET；`tb_csr` 的旧预期值已按 MPP/IALIGN 修正。Docker/Icarus 完整回归 `9 passed, 0 failed`；Vivado Simulator 2024.2 的两项 CSR 测试均通过。仍未进行 PDS 综合或上板验证。

### 2026-09-16 阶段 1：半字访存边界

- 使用与 SoC 一致的一拍同步 RAM 验证 `LH/LHU/SH`：`LH` 对 bit 15 符号扩展，`LHU` 零扩展；地址偏移 0 和 2 分别选择一个字的低、高半字。`SH` 只使能对应两个字节，分别产生 `0011` 和 `1100` 写掩码；`LW` 再读回核对最终小端字节序。
- 地址偏移 1/3 的 `LH/LHU/SH` 分别产生 Load/Store 未对齐 cause 4/6，`mtval` 保存有效地址；故障 Load 不覆盖目标寄存器，故障 Store 不拉高写使能。现有 RTL 通过了测试，本轮没有改动访存数据通路。
- `tb_halfword` 在 Docker/Icarus 与 Vivado Simulator 2024.2 均通过；完整项目回归为 `10 passed, 0 failed`。测试范围仍是固定一拍 RAM，不证明未来 Cache miss、总线等待或 FPGA 上板行为。

### 2026-09-16 阶段 1：上游 RV32UI 纯计算与控制流单测

- 单独的 `make isa-smoke` 固定使用 [riscv-tests](https://github.com/riscv-software-src/riscv-tests) 提交 `2ebecad997fa58cd9e5724340ba75aa4b59bd1d0`，编译未经修改的 30 项 RV32UI 测试主体，覆盖整数算术/逻辑、比较、移位、分支、跳转和高位立即数；30/30 通过。`add/addi` 还覆盖边界值、零寄存器、源/目标重叠及多种前递距离。
- 本仓库仅提供 M-only 启动/结束适配：程序从 ROM 地址 0 执行，结果用一次 Store 写到 RAM 最后一个字 `0x20000ffc`；`1` 表示通过，其他编码报告失败子项。故意失败的探针产生非零仿真退出并报告子项 7，验证测试桥接不会误报 PASS。
- 该次 30 项结果与项目自写的 `10/10` 回归分别统计。当时的桥接尚未装载 RAM 数据段或允许普通 RAM 写入；访存测试已在下一小节补入。没有使用上游默认的 PMP/SATP/U 模式环境，也没有运行 ACT4 或板级验证，不能把 30/30 宣称为官方一致性认证。

### 2026-09-16 阶段 1：上游 RV32UI 访存单测

- 仿真适配现按 ELF 的 `.data` 内容初始化 `0x20000000` 起的 4 KiB 同步 RAM，普通 Store 可修改数据区；最后一个字 `0x20000ffc` 只作为结果出口，Load、越界访问和非整字结果写入会报错。链接阶段也检查数据/零初始化段不覆盖结果字。
- 在原有 30 项之上加入 `lb/lbu/lh/lhu/lw/sb/sh/sw/ld_st/st_ld` 共 10 项。它们覆盖字节/半字/字、符号扩展、小端字节排列、普通 RAM 写入和写后读/前递距离；固定上游版本在 Docker/Icarus 下共 `40/40` 通过，故意失败的结果码探针继续正确失败。项目自写完整回归另为 `10/10`。
- 未纳入上游 `fence_i`（当前核心未实现 FENCE.I）和 `ma_data`（它要求未对齐访存直接成功，而本核策略是产生 Trap）。目前仍是 M-only、固定一拍 ROM/RAM 的行为仿真；没有运行 ACT4、完整 CSR/随机测试、综合或板级验证。

### 2026-09-16 阶段 1：固定种子长序列与独立参考值

- 新增本地 `long_mem_stress.S`：从 `0x12345678` 开始执行 256 轮 xorshift32，在 16 个 RAM 字间轮转，每轮交错使用移位/XOR、分支、`SW/LW`、`SH/LH`、`SB/LB` 和紧邻的写后读。程序内检查即时结果及最终状态；宿主机另行计算 16 个最终 RAM 字作为独立参考值。
- Docker/Icarus 下运行 12,403 仿真周期并通过；测试台还会故意提交错误参考值，确认它确实会报错。上游 40/40 与项目完整回归 10/10 保持通过。本轮未改 CPU RTL。
- 数据按固定种子变化，但指令顺序是固定循环；这不是随机指令生成、ACT4、Cache miss/可等待总线验证，也不代表 FreeRTOS 或上板长时间稳定性。

### 2026-09-16 阶段 1：可复现的随机指令混合与 ACT4 预检

- 生成器用 4 个固定种子各生成 96 条不同顺序的 RV32I 运算指令，每组均包含 `ADDI/XORI/ANDI/ORI/SLLI/SRLI/SRAI/ADD/SUB/XOR`。每 8 条插入 Store→Load→Branch 检查，末尾的 RAM 字与生成器的 32 位宿主机模型比较；四组均通过，且错误参考值探针仍能被拒绝。
- 这是真正变化的指令顺序，但仅覆盖选定的 10 类运算和固定一拍 RAM；未随机化异常、中断或 Cache 等待。种子写死以便复现失败，后续可以扩大种子集合。
- 按 [ACT4 官方说明](https://github.com/riscv/riscv-arch-test/blob/act4/README.md)，完整适配还需 UDB 硬件配置、`rvmodel_macros.h`、链接脚本和 Sail 参考模型。当前 Docker 有 RISC-V GCC/Icarus，但没有 Python/uv、Ruby/Bundler 或 Sail；本轮只做只读预检，未安装依赖、未运行 ACT4。可考虑以后使用其[独立 Docker 环境](https://github.com/riscv/riscv-arch-test/blob/act4/Dockerfile)，避免改动现有轻量仿真环境。

### 2026-09-16 阶段 1：交叉 Trap、FENCE 与行为基线验收

- `tb_trap_mix` 运行真实 M-mode Handler：64 次主循环中交错 Store/Load 与 ECALL；处理 8 次 ECALL、18 次定时器中断，包含同周期 ECALL/Timer 冲突、Load EX 与 Timer 重合及 Store EX 与 Timer 重合。Handler 保存临时寄存器、修正 ECALL 的 `mepc` 后 MRET；最终 RAM 计数由测试台独立核对。4 个固定脉冲时序种子在 Docker/Icarus 和 Vivado Simulator 2024.2 均通过。
- 新增 RV32I `FENCE` 译码：当前单核顺序执行、固定一拍存储且无未完成请求，FENCE/FENCE.TSO 可在无额外硬件等待下退休；保留的 `fm/rs1/rd` 也按普通 FENCE 处理。`tb_fence` 验证 Store→FENCE→Load、3 条 FENCE 正常退休且无多余写入；未实现的 FENCE.I 单独产生 cause 2、`mtval=0x0000100f`，Handler 跳过后能继续执行。Icarus 与 Vivado Simulator 2024.2 均通过。接入 Cache、突发总线或 AI DMA 前须重做排序契约，不能沿用“空操作”结论。
- 最终串行入口 `make phase1-behavior` 依次运行项目完整回归、固定上游 RV32UI 40 项、本地 256 轮长序列、4 种子×96 条随机运算及 4 种子异常/中断交错；最终项目回归为 11/11。此结论限于已实现的 M-only 指令/CSR 子集和一拍同步 ROM/RAM 行为模型；并不覆盖 ACT4、可等待总线、综合时序或上板。

### 与后续 Cache 和分支预测器的控制关系

- 中断、分支预测失败和 Cache 异常都需要同一套“重定向 PC + kill 年轻指令 + 禁止错误副作用”的恢复机制；当前 `valid/kill/commit` 是这三者共享的正确性基础。
- 分支预测器以后需要把 `pred_taken/pred_target` 等预测信息随有效指令带到 EX，在预测失败时复用现有高优先级重定向和冲刷通路。
- Cache 以后只能为有效访存发起请求，Store 必须在允许提交时才对外可见；Cache miss 产生的暂停还必须保持各级 `valid`，不能把同一请求重复发送。
- 当前已具备 EX/MEM/WB 有效位、统一 PC 重定向优先级、副作用门控和 Timer pending；尚缺 IF/ID 与存储接口的 `valid/ready` 握手、未完成请求标识，以及分支预测元数据流水寄存器。

尚未验证：

- RV32I/Zicsr 官方一致性测试；
- 除中断用例外，Icarus 与 Vivado Simulator 的完整功能一致性；
- 综合、实现、DRC、CDC、利用率和时序；
- bitstream 身份与板级 UART；
- FreeRTOS 启动、tick、上下文切换和长时间运行。

## 后续开发优先级

### 已完成的行为基线

- 阶段 1 的 M-only、一拍同步存储行为验收已完成；每项结果及其限制见上文和 [升级计划](升级计划.md)。`timer_int` 在 SoC 中仍接 0，真实定时器、CDC、UART 自检、ACT4 和 FreeRTOS 端到端测试尚待完成。
- `.mem` 镜像已按 4 KiB ROM 生成并检查越界；`sample.ld` 仍声明 128 KiB ROM/RAM，扩大实际存储器或运行更大软件前必须统一。

### 下一步：阶段 2 存储接口与目标流水线

1. 为取指、Load/Store 定义可等待、可报错的请求/响应协议；验证停顿中不重复 Store、重定向后不执行过期取指响应。
2. 按赛题目标把合并的取指/译码前端拆为明确的 IF、ID 两级，将现有 `valid/kill/commit` 扩展到真实五级流水；保持阶段 1 的精确异常语义。
3. 划定 ROM、普通 RAM、非缓存 MMIO 和后续 DMA 缓冲区；预留 DDR 突发与仲裁接口。每次改动后重跑 `make phase1-behavior`，并增加可变等待/错误返回测试。

### 并行的工程与软件验收

- 为盘古100Pro+的 `PG2L100H-6FBG676` 建立目标 PDS 工程和约束，先测 CPU/DDR IP 的真实 LUT6、DRM、APM 占用与布线后时序；仓库中的 `rtl/phosphor_zynq.xdc` 是旧 Xilinx 约束，不可直接迁移。
- 适配目标存储容量、链接脚本、启动与 UART/定时器软件后再跑 CoreMark 和 FreeRTOS；在此之前不能报告板级 CoreMark/MHz 或 CoreMark/LUT。
- legacy RTL 与旧 Draw.io 架构资料继续标为参考文件；若重画架构图，应以当前端口、位宽和 CSR 路径为准，不混入活跃源码。

## 项目结构

```text
risc-mini-NailongBranch2/
├── .devcontainer/          # Debian 开发容器和工具安装
├── .vscode/                # Verilog/C 工具配置
├── rtl/
│   ├── soc.sv              # 当前 SoC 顶层
│   ├── phosphor_zynq.xdc   # 50 MHz 与四个顶层引脚约束
│   ├── core/               # 当前 pipeline 核心及 legacy CPU
│   └── peripherals/        # 总线、ROM、RAM、UART、复位
├── sim/                    # 自检 testbench 与 ISA/Trap 仿真脚本
├── src/
│   ├── hello/              # 当前默认 Hello World 应用
│   ├── mini_libc/          # 当前 SoC UART 的 picolibc 适配
│   ├── FreeRTOS/           # 尚未完成 SoC 适配的移植素材
│   ├── document/           # 旧设计报告与 Draw.io 架构资料
│   ├── config.mk           # 交叉工具链与 ISA/ABI 配置
│   ├── sample.ld           # 当前构建使用的内存参数
│   └── risc-mini.mem/.coe  # 当前提交的程序镜像
├── Makefile
├── LICENSE
└── README.md
```

`src/document/arch` 中的 Draw.io 和 PNG 可用于理解历史设计，但多张图存在旧端口、位宽或 CSR 连线错误。`src/document/Classno.1Teamno.3_20260306.doc` 的版本记录更新到 2026-04-04，验证章节仍为空，并保留了中断/Trap 的已知问题说明。后续开发以 RTL 和可重复测试为准。

## 开发约定

- 新 CPU 功能默认修改 `rtl/core/pipeline.sv` 主线，不在 `cpu.sv/data_path.sv` 上平行演进。
- 任何周期级行为变化都应新增或更新一个自检 testbench，并记录使用的存储器时序模型。
- “已实现”表示 RTL 路径存在；“已验证”必须同时说明仿真器、测试、综合/时序或板级证据。
- 修改地址映射、CSR、Trap 或软件 ABI 时，同步更新本文、链接脚本、头文件和测试镜像。
- 在声称 FreeRTOS 可用前，至少保留启动、周期 tick、任务切换、UART 输出和长时间运行记录。

## License

项目根目录代码采用 [MIT License](LICENSE)。`src/FreeRTOS` 中的上游文件保留各自的版权和 MIT/SPDX 声明。
