# risc-mini

基于verilog的risc-V的cpu课程设计。

## Features

- [x] 支持RV32IM：RISC-V 32位基础整数指令集，乘法和除法扩展，共40+8条指令
- [x] 采用三级流水线，即 Fetch取指，Decode译码 和 Execute执行

## Getting Started

这里介绍基于vscode的开发环境搭建，也可以使用vivado作为IDE。

### 首先安装以下软件：

- iverilog：轻量仿真工具，包含iverilog，vvp
- vscode：代码编辑器
- ctags：代码索引工具，用于代码跳转
- riscv-none-gcc：risc-v编译器，用于编译生成可执行文件[github release](https://github.com/ilg-archived/riscv-none-gcc/releases/) 或者使用apt中的 gcc-riscv64-unknown-elf 作为代替

注意，windows下iverilog自带gtkwave波形显示工具，不需要额外安装。ctags需要universal-ctags而不是老版本的。

### 接着安装vscode插件：

- Verilog HDL：配合iverilog，ctags实现语法检查和代码跳转
- WaveTrace：显示波形图，当然也可以用gtkwave

### 最后进行插件配置：

在.vscode文件夹中创建settings.json

```json
{
    "verilog.linting.linter": "iverilog",
    "verilog.linting.iverilog.includePath": [
        "rtl/core"
    ],
    "verilog.linting.iverilog.arguments": "-y rtl/core"
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