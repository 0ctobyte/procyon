.DEFAULT_GOAL := sim

include ../common/common.mk

TESTS_RUN_DIR := $(TESTS_DIR)

# GCC command-line arguments for test code
TESTS_SRC := $(wildcard *.S)
TESTS := $(patsubst %.S, %, $(TESTS_SRC))
TESTS_OUT := $(foreach test, $(TESTS), $(TESTS_DIR)/$(test))
LINK_FILE := link.ld
CFLAGS := -march=rv32g -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles  -T$(LINK_FILE)

.PHONY: build-only sim
build-only: $(VDUTS_OUT) $(TESTS_OUT)

sim: $(VDUTS_OUT) $(TESTS_OUT)
	$(TESTS_RUN_SCRIPT) --timeout 120 -e ".dump" $(OBJ_DIR) $(TESTS_RUN_DIR)

$(TESTS_DIR)/%: %.S
	$(MKDIR) -p $(TESTS_DIR)
	$(CC) $(CFLAGS) $< -o $@
	$(OBJDUMP) -m riscv:rv32 -EL -D $@ > $@.dump
