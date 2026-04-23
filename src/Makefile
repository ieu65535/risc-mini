include config.mk

# Add your application here:
APPLICATION = FreeRTOS
# APPLICATION = hello

PROJ = risc-mini

TARGETS = $(PROJ).disasm $(PROJ).mem $(PROJ).coe
DEPS = $(APPLICATION)/$(APPLICATION).elf

all: $(TARGETS) $(DEPS)
	@echo build is ok for $(TARGETS)

$(DEPS):
	make -C $(APPLICATION) all

$(PROJ).bin: $(DEPS) Makefile
	$(OC) $(OCFLAGS) $< $@

PMEM_DEPTH=12
PMEM_SIZE=$(shell echo $$((4<<$(PMEM_DEPTH))))

$(PROJ).mem: $(PROJ).bin
	cat $< /dev/zero | head -c $(PMEM_SIZE) | hexdump -ve '/4 "%.8x\n"' > $@

# 生成 Xilinx COE 文件用于 BRAM 初始化
$(PROJ).coe: $(PROJ).bin
	@echo "memory_initialization_radix=16;" > $@
	@echo "memory_initialization_vector=" >> $@
	hexdump -ve '/4 "%.8x\n"' $< | sed 's/$$/,/' | sed '$$ s/,/;/' >> $@

$(PROJ).disasm: $(DEPS) Makefile
	$(OD) -s -d $< > $@

clean:
	make -C $(APPLICATION) clean
	-rm -f *.o *.bin *.mem *.coe *.disasm

.PHONY: all clean