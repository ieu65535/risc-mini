include ../config.mk
OUTPUT_DIR := ./build

PROJ = FreeRTOS

TARGETS = $(PROJ).elf

KERNEL_DIR = ./Source
KERNEL_PORT_DIR += $(KERNEL_DIR)/portable/RISC-V
INCLUDE_DIRS += -I$(KERNEL_DIR)/include \
				-I$(KERNEL_PORT_DIR)
VPATH += $(KERNEL_DIR) $(KERNEL_PORT_DIR) $(KERNEL_DIR)/portable/MemMang
SOURCE_FILES += $(KERNEL_DIR)/tasks.c
SOURCE_FILES += $(KERNEL_DIR)/list.c
SOURCE_FILES += $(KERNEL_DIR)/queue.c
SOURCE_FILES += $(KERNEL_DIR)/timers.c
SOURCE_FILES += $(KERNEL_DIR)/event_groups.c
SOURCE_FILES += $(KERNEL_DIR)/stream_buffer.c
SOURCE_FILES += $(KERNEL_DIR)/portable/MemMang/heap_4.c
SOURCE_FILES += $(KERNEL_PORT_DIR)/port.c
ASM_SOURCE_FILES += $(KERNEL_PORT_DIR)/portASM.S

DEMO_ROOT = ./Demo
COMMON_DEMO_FILES = $(DEMO_ROOT)/Common/Minimal
INCLUDE_DIRS += -I$(DEMO_ROOT)/Common/include
VPATH += $(COMMON_DEMO_FILES)
SOURCE_FILES += $(COMMON_DEMO_FILES)/AbortDelay.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/BlockQ.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/blocktim.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/countsem.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/death.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/dynamic.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/EventGroupsDemo.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/GenQTest.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/integer.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/IntSemTest.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/MessageBufferAMP.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/MessageBufferDemo.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/PollQ.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/QPeek.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/QueueOverwrite.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/QueueSet.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/QueueSetPolling.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/recmutex.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/semtest.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/StaticAllocation.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/StreamBufferDemo.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/StreamBufferInterrupt.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/TaskNotify.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/TaskNotifyArray.c
SOURCE_FILES += $(COMMON_DEMO_FILES)/TimerDemo.c

DEMO_PROJECT = .
VPATH += $(DEMO_PROJECT)
INCLUDE_DIRS += -I$(DEMO_PROJECT)
SOURCE_FILES += $(DEMO_PROJECT)/main.c
SOURCE_FILES += $(DEMO_PROJECT)/main_blinky.c
SOURCE_FILES += $(DEMO_PROJECT)/main_full.c
SOURCE_FILES += $(DEMO_PROJECT)/ns16550.c
SOURCE_FILES += $(DEMO_PROJECT)/riscv-virt.c

ASM_SOURCE_FILES += ./start.S
ASM_SOURCE_FILES += ./RegTest.S
ASM_SOURCE_FILES += ./vector.S

CFLAGS += $(INCLUDE_DIRS)

#Create a list of object files with the desired output directory path.
OBJS = $(SOURCE_FILES:%.c=%.o) $(ASM_SOURCE_FILES:%.S=%.o)
OBJS_NO_PATH = $(notdir $(OBJS))
OBJS_OUTPUT = $(OBJS_NO_PATH:%.o=$(OUTPUT_DIR)/%.o)

#Create a list of dependency files with the desired output directory path.
DEP_FILES := $(SOURCE_FILES:%.c=$(OUTPUT_DIR)/%.d) $(ASM_SOURCE_FILES:%.S=$(OUTPUT_DIR)/%.d)
DEP_FILES_NO_PATH = $(notdir $(DEP_FILES))
DEP_OUTPUT = $(DEP_FILES_NO_PATH:%.d=$(OUTPUT_DIR)/%.d)

all: $(TARGETS)
	@echo sources ok for $(TARGETS).

%.o : %.c
$(OUTPUT_DIR)/%.o : %.c $(OUTPUT_DIR)/%.d Makefile
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

%.o : %.S
$(OUTPUT_DIR)/%.o: %.S $(OUTPUT_DIR)/%.d Makefile
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

$(TARGETS): $(OBJS_OUTPUT) Makefile
	$(CC) $(OBJS_OUTPUT) $(LDFLAGS) -o $(TARGETS)
	$(SIZE) $(TARGETS)

$(DEP_OUTPUT):
include $(wildcard $(DEP_OUTPUT))

clean:
	rm -f $(TARGETS) $(OUTPUT_DIR)/*.o $(OUTPUT_DIR)/*.d $(OUTPUT_DIR)/*.map

.PHONY: all rtos clean
