default: src/risc-mini.bin
	make -C sim

regression:
	$(MAKE) -C src all
	bash sim/run_regression.sh

regression-all:
	$(MAKE) -C src all
	bash sim/run_regression.sh --all

isa-smoke:
	bash sim/run_isa_smoke.sh

trap-mix:
	bash sim/run_trap_mix.sh

phase1-behavior:
	$(MAKE) regression-all
	$(MAKE) isa-smoke
	$(MAKE) trap-mix

all:
	make -C src all
	make -C sim all

src/risc-mini.bin:
	make -C src all

clean:
	make -C src clean
	make -C sim clean

.PHONY: default all clean regression regression-all isa-smoke trap-mix phase1-behavior
