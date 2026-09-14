#开发板约束文件

#时序约束
create_clock -period 20.000 -name clk [get_ports clk] 

#IO约束文件

#----------------------系统时钟---------------------------
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports clk]

#----------------------系统复位---------------------------
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports rst_n]

#----------------------PL_UART---------------------------
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports rxd]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports txd]