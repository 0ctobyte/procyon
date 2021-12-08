CC := riscv64-unknown-elf-gcc
VERILATOR = verilator
MAKE := make
MKDIR := mkdir
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump

THREADS ?= 4
IC_LINE_SIZE ?= 32

OBJ_DIR := obj_dir
DUT := dut
DUT_SRC := ../common/$(DUT).sv
SYSC_CFLAGS := -CFLAGS -I../../common -CFLAGS -DIC_LINE_SIZE=$(IC_LINE_SIZE)
SYSC_SRCS := ../common/sc_main.cpp ../common/utils.cpp
VSRCS := ../../rtl/lib/procyon_lib_pkg.sv ../../rtl/system/procyon_system_pkg.sv ../../rtl/core/procyon_core_pkg.sv $(filter-out %_pkg.sv, $(wildcard ../../rtl/*/*.sv))
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -GOPTN_IC_LINE_SIZE=$(IC_LINE_SIZE) -Wall -Wno-fatal --trace --top-module $(DUT) --sc --exe
VDUT := V$(DUT)
LINK_FILE := link.ld
CFLAGS := -march=rv32g -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles  -T$(LINK_FILE)
TESTS_SRC := $(wildcard *.S)
TESTS := $(patsubst %.S, %, $(TESTS_SRC))
TESTS_DIR := tests
TESTS_OUT := $(foreach test, $(TESTS), $(TESTS_DIR)/$(test))

TESTS_RUN_DIR := $(TESTS_DIR)
TESTS_RUN_SCRIPT := ../run-tests.py

.PHONY: all sim clean
all: $(OBJ_DIR)/$(VDUT) $(TESTS_OUT)

sim: $(OBJ_DIR)/$(VDUT) $(TESTS_OUT)
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)
	$(TESTS_RUN_SCRIPT) --timeout 120 -e ".dump" $(OBJ_DIR)/$(VDUT) $(TESTS_RUN_DIR)

clean:
	rm -rf $(OBJ_DIR) $(TESTS_DIR) *.vcd

$(OBJ_DIR)/$(VDUT): $(OBJ_DIR)/$(VDUT).mk
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)

$(OBJ_DIR)/$(VDUT).mk: $(SYSC_SRCS) $(VSRCS) $(DUT_SRC)
	$(VERILATOR) --threads $(THREADS) $(SYSC_CFLAGS) $(VINCLUDE) $(VFLAGS) $(VSRCS) $(DUT_SRC) $(SYSC_SRCS) --prefix $(VDUT)

$(TESTS_DIR)/%: %.S
	$(MKDIR) -p $(TESTS_DIR)
	$(CC) $(CFLAGS) $< -o $@
	$(OBJDUMP) -m riscv:rv32 -EL -D $@ > $@.dump
