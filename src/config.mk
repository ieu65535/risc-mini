ifndef CROSS
	CROSS = riscv64-unknown-elf
	CCPATH = /usr/bin
endif

ARCH = rv32i_zicsr
ABI = ilp32
CMODEL = medlow
LIBC = mini_libc
INCLUDE_DIRS += -I../$(LIBC)/include
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

LDFLAGS += --specs=picolibc.specs -T../sample.ld --printf=i
LDFLAGS += -march=$(ARCH) -mabi=$(ABI) -mcmodel=$(CMODEL)

LDLIBS  = $(LIBS)
CPFLAGS = -P 
OCFLAGS = -j .rodata -j .init -j .text -j .data -O binary
ODFLAGS = -D
ARFLAGS = -rcs

VPATH += ../$(LIBC)
SOURCE_FILES += ../$(LIBC)/uart.c