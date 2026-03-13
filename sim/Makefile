
ifndef ICARUS
    ICARUS = iverilog -Wall
    VVP = vvp
endif

RTLS =  tb_soc.v                        \
        ../rtl/soc.v                    \
        ../rtl/core/cpu.v               \
        ../rtl/core/alu.v               \
        ../rtl/core/reg_file.v          \
        ../rtl/peripherals/bus.v        \
        ../rtl/peripherals/flash.v      \
        ../rtl/peripherals/ram.v        \
        ../rtl/peripherals/io.v         \
        ../rtl/peripherals/reset_sync.v \
        ../rtl/peripherals/uart_rx.v    \
        ../rtl/peripherals/uart_tx.v    \

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