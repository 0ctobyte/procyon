CC := riscv64-unknown-elf-gcc
VERILATOR = verilator
MAKE := make
MKDIR := mkdir
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump

THREADS ?= 4
NUM_MODELS ?= 5

OBJ_DIR := obj_dir
DUT := dut
DUT_SRC := ../common/$(DUT).sv
SYSC_CFLAGS := -CFLAGS -I../../common
SYSC_SRCS := ../common/sc_main.cpp ../common/utils.cpp
SYSC_SRCS_PATH := $(foreach src, $(SYSC_SRCS), ../../$(src))
VSRCS := ../../rtl/lib/procyon_lib_pkg.sv ../../rtl/system/procyon_system_pkg.sv ../../rtl/core/procyon_core_pkg.sv $(filter-out %_pkg.sv, $(wildcard ../../rtl/*/*.sv))
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -Wall -Wno-fatal --trace --top-module $(DUT) --sc --exe
VDUT := V$(DUT)
VDUTS_OUT := $(foreach num, $(shell seq $(NUM_MODELS)), $(OBJ_DIR)/$(VDUT)$(num)/$(VDUT))
LINK_FILE := link.ld
CFLAGS := -march=rv32g -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles  -T$(LINK_FILE)
TESTS_SRC := $(wildcard *.S)
TESTS := $(patsubst %.S, %, $(TESTS_SRC))
TESTS_DIR := tests
TESTS_OUT := $(foreach test, $(TESTS), $(TESTS_DIR)/$(test))
PARAMETER_SPEC := ../common/$(DUT).json

TESTS_RUN_DIR := $(TESTS_DIR)
TESTS_RUN_SCRIPT := ../run-tests.py
GEN_MODEL_SCRIPT := ../gen-model.py

.PRECIOUS: %/$(VDUT).json
.PHONY: all sim clean
all: $(VDUTS_OUT)  $(TESTS_OUT)

sim: $(VDUTS_OUT)  $(TESTS_OUT)
	$(TESTS_RUN_SCRIPT) --timeout 120 -e ".dump" $(OBJ_DIR) $(TESTS_RUN_DIR)

clean:
	rm -rf $(OBJ_DIR) $(TESTS_DIR) *.vcd

%/$(VDUT): %/$(VDUT).mk
	$(MAKE) -C $(@D) -f $(@F).mk $(@F)

%/$(VDUT).mk: %/$(VDUT).json $(SYSC_SRCS) $(VSRCS) $(DUT_SRC)
	$(VERILATOR) --threads $(THREADS) $(SYSC_CFLAGS) $(VINCLUDE) $(shell $(GEN_MODEL_SCRIPT) -v $<) $(VFLAGS) $(VSRCS) $(DUT_SRC) $(SYSC_SRCS_PATH) --Mdir $(@D) --prefix $(VDUT)

%/$(VDUT).json: $(PARAMETER_SPEC)
	mkdir -p $(@D)
	$(GEN_MODEL_SCRIPT) -g $< -o $@

$(TESTS_DIR)/%: %.S
	$(MKDIR) -p $(TESTS_DIR)
	$(CC) $(CFLAGS) $< -o $@
	$(OBJDUMP) -m riscv:rv32 -EL -D $@ > $@.dump
