# risc-mini

基于verilog的risc-V的cpu课程设计。

## Features

- [x] 支持RV32I：RISC-V 32位基础整数指令集，共37条指令（不包括FENCE、ECALL、EBREAK）
- [x] uart：支持uart串口通信
- [ ] 添加Zicsr状态寄存器控制支持
- [ ] 添加中断支持
- [ ] 添加定时器支持
- [ ] 添加FreeRTOS支持
- [ ] 采用三级流水线，即 Fetch取指，Decode译码 和 Execute执行

## Getting Started

这里介绍基于vscode的开发环境搭建，也可以使用vivado作为IDE。

### 方案一：dev containers 插件

vscode的dev containers插件可以在docker容器中搭建开发环境，避免了环境配置的麻烦，推荐使用。

需要安装docker或者podman。windows环境下可以安装Docker Desktop或者podman desktop。docker和podman的官网都有较为详细的dev containers环境配置教程

### 方案二：手动安装环境

#### 首先安装以下软件：

- iverilog：轻量仿真工具，包含iverilog，vvp
- vscode：代码编辑器
- ctags：代码索引工具，用于代码跳转

如果需要编译C语言代码，还需要安装（建议在linux下安装）：

- gcc-riscv64-unknown-elf：risc-v编译器，用于编译生成可执行文件，或者使用[github release](https://github.com/ilg-archived/riscv-none-gcc/releases/)作为代替
- picolibc-riscv64-unknown-elf：嵌入式C语言库

注意，windows下iverilog自带gtkwave波形显示工具，不需要额外安装。ctags需要universal-ctags而不是老版本的。

#### 接着安装vscode插件：

- Verilog HDL：配合iverilog，ctags实现语法检查和代码跳转
- WaveTrace：显示波形图，当然也可以用gtkwave

#### 最后进行插件配置：

在.vscode文件夹中创建settings.json

```json
{
    "verilog.linting.linter": "iverilog",
    "verilog.linting.iverilog.includePath": [
        "rtl/core",
        "rtl"
    ],
    "verilog.linting.iverilog.arguments": "-y rtl/core -y rtl/peripherals -y rtl"
}
```

这里，通过-y参数指定模块源代码iverilog可以实现多文件的语法检查。不过限制在于，模块名字必须和文件名一样，否则会找不到模块。这并不意味着一个文件只能有一个模块，更准确的理解方式是，默认“导出”和文件同名的模块，其他模块不导出。

## 项目结构

```
risc-mini/
├── rtl/
│   ├── core/
│   └── peripherals/
├── sim/
├── src/
├── LICENSE
├── Makefile
└── README.md
```

- rtl：存放verilog代码
- sim：存放testbench仿真文件
- src：存放C语言代码，用于生成可执行文件

## 编译和仿真

使用make命令运行默认仿真，make all运行编译，并仿真

```
make

make all
make clean
```

编译c代码前，需先修改src/config.mk配置文件，指定编译器路径。

在Makefile中，可以通过APPLICATION变量指定运行的子项目，目前暂时不支持FreeRTOS。

