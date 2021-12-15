# Variable overrides
NUM_MODELS ?= 5
THREADS ?= 4

# Tools
CC := riscv64-unknown-elf-gcc
VERILATOR = verilator
MAKE := make
MKDIR := mkdir
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump
TESTS_RUN_SCRIPT := ../../scripts/run-tests.py
GEN_MODEL_SCRIPT := ../../scripts/gen-model.py

OBJ_DIR := obj_dir
DUT := dut
DUT_SRC := ../common/$(DUT).sv
PARAMETER_SPEC := ../common/$(DUT).json

# Verilator command-line arguments
SYSC_CFLAGS := -CFLAGS -I../../common
SYSC_SRCS := ../common/sc_main.cpp ../common/utils.cpp
SYSC_SRCS_PATH := $(foreach src, $(SYSC_SRCS), ../../$(src))
VSRCS := ../../rtl/lib/procyon_lib_pkg.sv ../../rtl/system/procyon_system_pkg.sv ../../rtl/core/procyon_core_pkg.sv $(filter-out %_pkg.sv, $(wildcard ../../rtl/*/*.sv))
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -Wall -Wno-fatal --trace --top-module $(DUT) --sc --exe

VDUT := V$(DUT)
VDUTS_OUT := $(foreach num, $(shell seq $(NUM_MODELS)), $(OBJ_DIR)/$(VDUT)$(num)/$(VDUT))

TESTS_DIR := tests

.PRECIOUS: %/$(VDUT).json
.PHONY: distclean clean

distclean: clean
	rm -rf $(TESTS_DIR)

clean:
	rm -rf $(OBJ_DIR) *.vcd

%/$(VDUT): %/$(VDUT).mk
	$(MAKE) -C $(@D) -f $(@F).mk $(@F)

%/$(VDUT).mk: %/$(VDUT).json $(SYSC_SRCS) $(VSRCS) $(DUT_SRC)
	$(VERILATOR) --threads $(THREADS) $(SYSC_CFLAGS) $(VINCLUDE) $(shell $(GEN_MODEL_SCRIPT) -v $<) $(VFLAGS) $(VSRCS) $(DUT_SRC) $(SYSC_SRCS_PATH) --Mdir $(@D) --prefix $(VDUT)

%/$(VDUT).json: $(PARAMETER_SPEC)
	$(MKDIR) -p $(@D)
	$(GEN_MODEL_SCRIPT) -g $< -o $@
