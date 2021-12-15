PROGRAM ?= fill4_move4skip32_compare4skip32

include ../common/common.mk

# GCC command-line arguments for test code
TESTS_SRC_DIR := ../../tb/lsu
TESTS_SRC := $(wildcard $(TESTS_SRC_DIR)/*.S)
TESTS_OUT := $(patsubst $(TESTS_SRC_DIR)/%.S, $(TESTS_DIR)/%, $(TESTS_SRC))
LINK_FILE := ../../tb/lsu/link.ld
CFLAGS := -march=rv32g -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles  -T$(LINK_FILE)

$(HEX_FILE): $(TESTS_OUT)
	mkdir -p $(HEX_DIR)
	$(HEXIFY_SCRIPT) -e ".dump" -e ".hex" -w $(IC_LINE_SIZE) $(TESTS_DIR)/$(PROGRAM) $(HEX_DIR)

$(TESTS_DIR)/%: $(TESTS_SRC_DIR)/%.S
	$(MKDIR) -p $(TESTS_DIR)
	$(CC) $(CFLAGS) $< -o $@
	$(OBJDUMP) -m riscv:rv32 -EL -D $@ > $@.dump
