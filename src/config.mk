ifndef CROSS
	CROSS = riscv64-unknown-elf
	CCPATH = /usr/bin
endif

ARCH = rv32i_zicsr
ABI = ilp32
CMODEL = medlow
LIBC =
INCLUDE_DIRS += -I$(LIBC)/include -I../$(LIBC)/include
INCLUDE_DIRS += -I/usr/lib/picolibc/riscv64-unknown-elf/include

CC   = $(CCPATH)/$(CROSS)-gcc
AS   = $(CCPATH)/$(CROSS)-as
RL   = $(CCPATH)/$(CROSS)-ranlib
LD   = $(CCPATH)/$(CROSS)-ld
OC   = $(CCPATH)/$(CROSS)-objcopy
OD   = $(CCPATH)/$(CROSS)-objdump
AR   = $(CCPATH)/$(CROSS)-ar
CPP  = $(CCPATH)/$(CROSS)-cpp
SIZE = $(CCPATH)/$(CROSS)-size

CFLAGS  = -Wall -Os -ffunction-sections -fdata-sections
CFLAGS += -march=$(ARCH) -mabi=$(ABI) -mcmodel=$(CMODEL)
ASFLAGS = -march=$(ARCH) -mabi=$(ABI)

LDFLAGS += --specs=picolibc.specs --oslib=semihost --crt0=minimal -DPICOLIBC_INTEGER_PRINTF_SCANF
LDFLAGS += -nostartfiles -Xlinker --gc-sections -Wl,-Map,$(OUTPUT_DIR)/RTOSDemo.map \
           -T../link.ld -march=$(ARCH) -mabi=$(ABI) -mcmodel=$(CMODEL) -Xlinker \
           --defsym=__stack_size=352 -Wl,--start-group -Wl,--end-group

LDLIBS  = $(LIBS)
CPFLAGS = -P 
OCFLAGS = -O binary
ODFLAGS = -D
ARFLAGS = -rcs