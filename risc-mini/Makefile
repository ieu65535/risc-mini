default: src/risc-mini.bin
	make -C sim

regression:
	$(MAKE) -C src all
	bash sim/run_regression.sh

regression-all:
	$(MAKE) -C src all
	bash sim/run_regression.sh --all

all:
	make -C src all
	make -C sim all

src/risc-mini.bin:
	make -C src all

clean:
	make -C src clean
	make -C sim clean

.PHONY: default all clean regression regression-all
