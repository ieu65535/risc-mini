# risc-mini NailongBranch2

这是一个用 SystemVerilog 实现的 32 位 RISC-V 教学 CPU/SoC。`NailongBranch2` 是团队当前完成度最高的历史分支，也是后续 CPU 开发的代码基线。

> 基线说明：本文依据 `NailongBranch2` 分支提交 `73970f7` 的 205 个受版本控制文件，于 2026-09-10 完成静态审计，并使用 Vivado Simulator 2024.2 做了独立编译、展开和行为仿真。代码、构建脚本和测试结果优先于旧设计报告与架构图。当前版本适合作为继续开发的起点，但尚不能视为通过 ISA 一致性、FreeRTOS、综合时序或板级验收的发布版本。

## 当前结论

- 当前 SoC 顶层是 [`rtl/soc.sv`](rtl/soc.sv)，当前 CPU 主线是 [`rtl/core/pipeline.sv`](rtl/core/pipeline.sv)。
- [`rtl/core/cpu.sv`](rtl/core/cpu.sv) 和 [`rtl/core/data_path.sv`](rtl/core/data_path.sv) 是未进入现有 SoC 与仿真文件表的旧实现，不应作为新功能入口。
- 主线核心是 RV32、单发射、顺序执行设计，包含取指/译码前端、EX、MEM、WB 四个逻辑处理阶段和三组级间寄存器。
- RTL 按设计意图覆盖 37 条常用 RV32I 指令，并加入六条 Zicsr 指令、ECALL、MRET、非法指令异常和一个实验性的机器定时器中断入口。
- UART、片上 ROM 和片上 RAM 已接入 SoC；GPIO 只有未使用的内部寄存器占位，定时器外设尚不存在。
- CPU 核心保留 `timer_int` 端口；当前 `soc` 将其明确固定为 0，避免悬空值进入控制逻辑。SoC 仍没有可用的定时器中断源。
- FreeRTOS 目录是混合版本、混合平台的参考移植素材：内核文件标记为 FreeRTOS Kernel V11.1.0，而配置、demo 与平台文件多为 V202212.00，并混有 QEMU `virt` 和另一套 SoC 的外设假设；尚未完成针对当前 SoC 的移植。

## 功能状态

| 子系统 | 当前状态 | 边界 |
| --- | --- | --- |
| RV32I 整数通路 | RTL 已实现，项目回归通过 | opcode、`funct3/funct7` 已严格检查；尚未做 riscv-arch-test |
| Zicsr | 实验性实现 | 六条 CSR 读改写指令有数据通路，但 CSR 权限、只读属性和非法访问异常未实现 |
| ECALL / MRET / 非法指令 | 第一版精确 Trap 已验证 | 支持 M 模式 ECALL cause 11、非法指令 cause 2 和 MRET；EBREAK 尚未单独实现 cause 3 |
| 地址未对齐异常 | 第一版已验证 | 支持 RV32I 控制流目标 cause 0、Load cause 4、Store cause 6；尚无 `mtval` |
| 机器定时器中断 | 核心第一版精确提交与请求保持已验证，SoC 暂时禁用 | 要求 `mstatus.MIE` 与 `mie.MTIE`；具有 `mip.MTIP` pending，但 SoC 仍没有同步器和 CLINT/mtime |
| 分支与冒险 | RTL 已实现 | Branch/JAL 静态预测跳转，JALR 在 EX 纠正；有 EX/MEM/WB 前递和 load-use 停顿 |
| UART | RTL 与 hello 软件已接入 | 尚无自检 UART testbench，也没有本次板级串口记录 |
| ROM / RAM | RTL 已实现 | 物理容量各 4 KiB，与镜像生成和链接脚本不一致 |
| GPIO | 未实现 | `PORTA` 仅声明，未做地址映射、读写或顶层引脚 |
| FreeRTOS | 未集成 | 目录内容仍面向 QEMU virt，不能直接在本 SoC 启动 |
| FPGA 工程 | 只有 RTL 和 XDC | 仓库没有 `.xpr`、器件型号、综合/实现报告或 bitstream |

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
| `rtl/core/decoder.sv` | RV32I 主 opcode、Zicsr、ECALL、MRET 译码 |
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

上述清单表示 RTL 的译码和数据通路意图，不等同于通过 RV32I compliance。译码器现严格检查支持指令的 opcode、`funct3` 和 `funct7`；未知或不支持的编码进入同步非法指令异常（cause 2），不会再静默表现为 NOP 或被别名为已有运算。FENCE/FENCE.I 尚未实现；EBREAK 目前也进入 cause 2，尚未实现独立的 breakpoint cause 3。

当前核心会检查非对齐访问：RV32I 控制流目标必须按 4 字节对齐，LH/SH 按 2 字节对齐，LW/SW 按 4 字节对齐；违例分别产生 cause 0、4、6，并由提交门控阻止故障指令产生副作用。JALR 先按规范清零目标 bit 0，再检查 bit 1。当前没有 `mtval`，也未覆盖错误配置的 `mtvec/mepc` 返回目标。数据通路是小端序。

### Zicsr 和 CSR

已接入 CSRRW、CSRRS、CSRRC、CSRRWI、CSRRSI、CSRRCI。当前 CSR 文件如下：

| CSR | 地址 | 当前行为 |
| --- | ---: | --- |
| `mstatus` | `0x300` | 存储 32 位；Trap/MRET 仅显式处理 MIE bit 3 和 MPIE bit 7 |
| `mie` | `0x304` | 可读写；`MTIE` bit 7 已接入机器定时器中断使能判断 |
| `mtvec` | `0x305` | 可读写；Trap 直接跳到原始值，不解析 Direct/Vectored 模式 |
| `mscratch` | `0x340` | 可读写 |
| `mepc` | `0x341` | 可读写；Trap 时保存 `pc_ex` |
| `mcause` | `0x342` | 可读写；当前生成指令地址未对齐 0、非法指令 2、Load 未对齐 4、Store 未对齐 6、ECALL 11 和机器定时器中断 `0x80000007` |
| `mip` | `0x344` | `MTIP` bit 7 只读反映已锁存 Timer 请求；请求真正被接收后由硬件清除 |
| `mhartid` | `0xF14` | 固定读 0 |

`cycle/cycleh` 虽有宏定义，但 CSR 文件没有实现，读取会返回默认值 0。除 `mip.MTIP` 外，其余 `mip` 位、`mtval`、MPP 等完整特权状态尚未实现，也没有 CSR 地址/权限异常。

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

- [`rtl/phosphor_zynq.xdc`](rtl/phosphor_zynq.xdc) 声明 20 ns 周期，即 50 MHz。
- 顶层端口为 `clk`、低有效 `rst_n`、`rxd`、`txd`。
- 当前引脚为 `clk/U18`、`rst_n/N16`、`rxd/T19`、`txd/J15`，均使用 LVCMOS33。
- `reset_sync` 对外部复位异步置位、同步两拍释放，并生成核心内部高有效 `rst`。
- PC 和级间寄存器使用同步高有效复位，CSR 文件使用异步高有效复位，GPR 没有复位。
- PC 复位为 `0xFFFF_FFFC`，组合的下一取指地址因此从 `0x0000_0000` 开始。

仓库没有 Vivado `.xpr` 或器件型号，无法从当前文件确认活动 source set、约束集、综合/实现 run 或 XDC 是否对应最终板卡。创建工程时，顶层应设为 `soc`，并先核对器件、板卡原理图、时钟源和四个管脚。

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
make -B -C sim TB_MOUDLE=tb_soc.sv
```

日常回归使用以下入口：

```bash
# 指令、冒险、控制流、CSR 和 SoC smoke test
make regression

# 在上述测试之外加入当前尚未闭环的异常/中断测试
make regression-all

# 只在调试单项测试时生成波形
make -B -C sim TB_MOUDLE=tb_control.sv DUMP_WAVES=1
```

每个 CPU testbench 只有在全部检查通过后才输出唯一的 `[TB PASS]` 标记；失败会累计并调用 `$fatal`。回归脚本还会检查进程状态、失败文本、超时、完成标记以及 SoC 的 `Hello, World!` UART 输出。标准回归保存到 `sim/regression.log`，含中断测试的完整回归保存到 `sim/regression-all.log`，便于宿主机直接检查。

## FreeRTOS 目录的真实状态

[`src/FreeRTOS`](src/FreeRTOS) 混合了 FreeRTOS Kernel V11.1.0 内核、V202212.00 配置/demo、RISC-V portable 层、QEMU virt 平台文件和另一套 SoC 示例。它目前是参考移植素材，不是已适配应用：

- `src/Makefile` 默认仍选择 `hello`；
- FreeRTOS 配置使用 25 MHz，而 XDC 和 `mini_libc` 使用 50 MHz；
- 配置期望 CLINT `mtime/mtimecmp` 位于 `0x0200_0000` 区域，当前 SoC 没有 CLINT；
- 示例代码使用 `0x1000_0000` 的 NS16550，另一些 UART 宏使用 `0x4000_4000`，当前 UART 实际位于 `0x4000_0000` 且寄存器布局不同；
- `main.c` 默认把 `mtvec` 配为 vectored 模式，当前核心只把 `mtvec` 原值当作 direct 入口；
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
| `sim/tb_interrupt.sv` | ECALL、MRET、非法指令、精确提交、mcause/mepc 和外部 timer 脉冲 |
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
- 当前边界：CSR 地址/权限尚未参与非法检查；EBREAK 尚无 cause 3。地址未对齐异常已在下一小节完成。

### 2026-09-16 阶段 1：地址未对齐异常

- EX 阶段使用最终有效地址检查 LH/LHU、LW、SH 和 SW 的自然对齐；故障 Load 不写回目标寄存器，故障 Store 不拉高任何内存写使能。
- 对 JAL、实际采用的 Branch 和 JALR 检查真实目标地址；RV32I 不含压缩指令，因此目标必须 4 字节对齐。未采用的条件分支不检查其未使用目标。
- 异常优先级现为同步地址异常/非法指令/ECALL 高于异步 Timer；cause 分别为指令地址 0、Load 4、Store 6。
- `tb_interrupt` 验证未对齐 LW 保留寄存器哨兵值、未对齐 SW 无写使能、未对齐 JAL 精确返回。Docker/Icarus 完整回归为 `6 passed, 0 failed`，Vivado Simulator 2024.2 同项通过并结束于 3205 ns。
- 当前边界：尚未实现 `mtval`，也未检查 MRET 的 `mepc` 或 Trap 的 `mtvec` 配置错误；后续还需扩充 LH/SH、JALR、taken/not-taken Branch 的交叉用例。

### 2026-09-16 阶段 1：Timer 请求保持

- 新增 `mip.MTIP` pending：同步的一拍 `timer_int` 即使发生在 MIE/MTIE 关闭期间也会被锁存，开放后在最早的精确指令边界接收。
- Timer 只有在赢得异常仲裁时才产生 `timer_irq_taken` 并清 pending；若与 ECALL 等同步异常同周期，先处理同步异常，Timer 保持到 MRET 后再处理。
- 已使能且没有更高优先级异常时，原始 `timer_int` 仍可当拍被接收，不额外增加正常中断延迟。
- `tb_interrupt` 覆盖 pending 的置位、跨 MIE/MTIE 屏蔽保持、接收后清除及 ECALL/Timer 冲突。Docker/Icarus 完整回归为 `6 passed, 0 failed`，Vivado Simulator 2024.2 同项通过并结束于 3735 ns。
- 当前接口约定 `timer_int` 与 CPU `clk` 同步且表示事件脉冲。未来接入异步引脚或标准电平型 `mtime/mtimecmp` 时，必须增加 CDC 同步并重新确定中断源清除/确认协议。

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

### P0 建立可信基线

1. 在 `soc` 明确连接 `timer_int`：未接定时器前固定为 0，接入后增加同步器和清晰的中断源接口。
2. 把 `pipeline.sv` 的所有信号声明移到首次使用之前，并同时用 Icarus 与 Vivado 重新回归。
3. 让每个 testbench 汇总错误数并在失败时调用 `$fatal`；修正失败后仍打印 `[PASS]` 的判定逻辑。
4. 统一 ROM/RAM 深度、`sample.ld`、`.mem/.coe` 生成长度和仿真加载路径。
5. 固化一条可重复的全量回归命令，并把日志中的 `[FAIL]`、`$error` 和 X 值视为失败。

### P1 完成可移植 CPU 行为

1. 已完成 EX/MEM/WB 第一版有效位和提交点；后续接入 IF/ID 与存储接口握手时继续扩展。
2. `mie.MTIE` 门控已接入；下一步实现正确的 `mtvec` Direct/Vectored 处理和必要的特权状态。
3. opcode、`funct3/funct7` 严格检查以及 illegal/misaligned Trap 已完成；下一步补 CSR 地址/权限检查。
4. 为指令和数据接口定义握手协议，或把“一拍同步返回、永不等待”写成稳定接口契约。
5. 增加 UART 自检、随机/定向冒险测试和官方 RISC-V ISA 测试。

### P2 SoC 与软件平台

1. 决定真实片上存储容量，并据此调整链接区、栈和 heap。
2. 为 FreeRTOS 实现本 SoC 的 UART、mtime/mtimecmp、启动代码、Trap 入口和端到端 demo。
3. 建立包含确切 FPGA part、top、XDC 和报告脚本的 Vivado 工程，完成综合、实现和板级验证。
4. 把 legacy RTL 和 Draw.io 备份文件移出活跃源码区，按当前 RTL 重画存在端口名、位宽和 CSR 来源错误的架构图。

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
├── sim/                    # 六个 SystemVerilog testbench
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
