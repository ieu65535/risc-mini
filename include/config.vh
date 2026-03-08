`ifdef __ICARUS__
    `define SIMULATION 1
`endif

`ifdef XILINX_ISIM
    `define SIMULATION 2
`endif

`ifdef MODEL_TECH
    `define SIMULATION 3
`endif

`ifdef XILINX_SIMULATOR
    `define SIMULATION 4
`endif

`ifndef FLASH_BASE
`define FLASH_BASE 32'h0000_0000    // Flash基地址
`endif

`ifndef RAM_BASE
`define RAM_BASE 32'h2000_0000      // RAM基地址
`endif

`ifndef REG_NUM
`define REG_NUM 32                   // 寄存器数量
`endif

`ifndef PC_RESET
`define PC_RESET 32'h0000_0000      // PC复位值
`endif