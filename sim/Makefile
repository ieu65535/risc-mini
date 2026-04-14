
ifndef ICARUS
    ICARUS = iverilog -g2005-sv
    VVP = vvp
endif

TB_MOUDLE = tb_soc.sv
# TB_MOUDLE = tb_dhazards.sv

RTLS =  $(TB_MOUDLE)                     \
        ../rtl/soc.sv                    \
        ../rtl/core/cpu.sv               \
        ../rtl/core/alu.sv               \
        ../rtl/core/ctrl.sv              \
        ../rtl/core/reg_file.sv          \
        ../rtl/core/pc_reg.sv            \
        ../rtl/core/data_path.sv         \
        ../rtl/core/pipeline.sv          \
        ../rtl/core/ex.sv                \
        ../rtl/core/wb.sv                \
        ../rtl/peripherals/bus.sv        \
        ../rtl/peripherals/flash.sv      \
        ../rtl/peripherals/ram.sv        \
        ../rtl/peripherals/io.sv         \
        ../rtl/peripherals/reset_sync.sv \
        ../rtl/peripherals/uart_rx.sv    \
        ../rtl/peripherals/uart_tx.sv    \

INCS = ../rtl/config.vh
XSIM = risc-mini.vvp
VCDS = risc-mini.vcd

.PRECIOUS: $(VCDS)  # Do not delete the trace file if simulation is aborted
.PHONY: $(VCDS)     # Always run the simulation

SRCS = ../src/risc-mini.mem

DEPS = $(SRCS) $(RTLS) $(INCS)

all: $(VCDS)
	@echo simulation ok.

clean:
	-rm -f $(VCDS) $(XSIM)

$(VCDS): $(XSIM)
	$(VVP) $<

$(XSIM): $(DEPS)
	$(ICARUS) -I ../rtl -I ../rtl/core -o $(XSIM) $(RTLS)