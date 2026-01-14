include config.mk

# Add your application here:
APPLICATION = FreeRTOS

PROJ = risc-mini

TARGETS = $(PROJ).disasm $(PROJ).mem
DEPS = $(APPLICATION)/$(APPLICATION).elf

all: $(TARGETS) $(DEPS)
	@echo build is ok for $(TARGETS)

$(DEPS):
	make -C $(APPLICATION) all

$(PROJ).bin: $(DEPS)
	$(OC) -j .rodata -j .init -j .text -j .data -O binary $< $@

$(PROJ).mem: $(PROJ).bin
	hexdump -ve '/4 "%.8x\n"' $< > $@

$(PROJ).disasm: $(DEPS)
	$(OD) -s -d $< > $@

clean:
	make -C $(APPLICATION) clean
	-rm -f *.o *.bin *.mem *.disasm

.PHONY: all clean