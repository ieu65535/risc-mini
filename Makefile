default: src/risc-mini.bin
	make -C sim

all:
	make -C src all
	make -C sim all

src/risc-mini.bin:
	make -C src all

clean:
	make -C src clean
	make -C sim clean
