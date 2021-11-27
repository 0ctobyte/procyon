CC := riscv64-unknown-elf-gcc
VERILATOR = verilator
MAKE := make
MKDIR := mkdir
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump

THREADS ?= 4

OBJ_DIR := obj_dir
DUT := dut
SYSC_CFLAGS := -I../../common
SYSC_SRCS := sc_main.cpp ../common/utils.cpp
VSRCS :=
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -Wall -Wno-fatal --trace --sc --exe
VDUT := V$(DUT)
LINK_FILE := link.ld
CFLAGS := -march=rv32g -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles  -T$(LINK_FILE)
TESTS := fill4_move4skip32_compare4skip32 move4skip32_compare4skip32 move4skip32dirty_compare4skip32 move1_compare1 move2_compare2 move4_compare4
TESTS_DIR := tests
TESTS_OUT := $(foreach test, $(TESTS), $(TESTS_DIR)/$(test))

TESTS_RUN_DIR := $(TESTS_DIR)
TESTS_RUN_SCRIPT := ../run-tests.py


.PHONY: all sim clean
all: $(TESTS_OUT) $(OBJ_DIR)/$(VDUT)

sim: $(TESTS_OUT) $(OBJ_DIR)/$(VDUT)
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)
	$(TESTS_RUN_SCRIPT) --timeout 120 -e ".dump" $(OBJ_DIR)/$(VDUT) $(TESTS_RUN_DIR)

clean:
	rm -rf $(OBJ_DIR) $(TESTS_DIR) *.vcd

$(OBJ_DIR)/$(VDUT): $(OBJ_DIR)/$(VDUT).mk
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)

$(OBJ_DIR)/$(VDUT).mk: $(SYSC_SRCS) $(DUT).sv
	$(VERILATOR) --threads $(THREADS) -CFLAGS $(SYSC_CFLAGS) $(VINCLUDE) $(VSRCS) $(VFLAGS) $(DUT).sv $(SYSC_SRCS) --prefix $(VDUT)

$(TESTS_DIR)/%: %.S
	$(MKDIR) -p $(TESTS_DIR)
	$(CC) $(CFLAGS) $< -o $@
	$(OBJDUMP) -m riscv:rv32 -EL -D $@ > $@.dump
