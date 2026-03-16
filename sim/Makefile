
ifndef ICARUS
    ICARUS = iverilog -Wall
    VVP = vvp
endif

RTLS =  tb_soc.sv                         \
        ../rtl/soc.sv                    \
        ../rtl/core/cpu.sv               \
        ../rtl/core/alu.sv               \
        ../rtl/core/reg_file.sv          \
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