quietly set StdArithNoWarnings 1
quietly set NumericStdNoWarnings 1

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv +incdir+../rtl +incdir+../rtl/core \
    tb_hello.sv \
    ../rtl/core/alu.sv \
    ../rtl/core/lmb.sv \
    ../rtl/core/ctrl.sv \
    ../rtl/core/decoder.sv \
    ../rtl/core/fetch.sv \
    ../rtl/core/forward.sv \
    ../rtl/core/reg_file.sv \
    ../rtl/core/pipeline.sv \
    ../rtl/core/ex.sv \
    ../rtl/core/wb.sv \
    ../rtl/core/csr_file.sv \
    ../rtl/peripherals/bus.sv \
    ../rtl/peripherals/ddr_interface.sv \
    ../rtl/peripherals/ram.sv \
    ../rtl/peripherals/io.sv \
    ../rtl/peripherals/uart_rx.sv \
    ../rtl/peripherals/uart_tx.sv

vsim -voptargs=+acc work.tb_hello
run -all
