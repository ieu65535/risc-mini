include ../config.mk
OUTPUT_DIR := ./build

PROJ = hello

TARGETS = $(PROJ).elf

SOURCE_FILES += ./main.c

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
