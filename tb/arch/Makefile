VERILATOR = verilator
MAKE := make

NUM_MODELS ?= 10

RISCV_ARCH_TESTS := ../../riscv-tests

OBJ_DIR := obj_dir
DUT := dut
DUT_SRC := ../common/$(DUT).sv
CFLAGS := -CFLAGS -I../../common
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -Wall -Wno-fatal --trace --top-module $(DUT) --sc --exe
VDUT := V$(DUT)
VDUTS_OUT := $(foreach num, $(shell seq $(NUM_MODELS)), $(OBJ_DIR)/$(VDUT)$(num)/$(VDUT))
VSRCS := ../../rtl/lib/procyon_lib_pkg.sv ../../rtl/system/procyon_system_pkg.sv ../../rtl/core/procyon_core_pkg.sv $(filter-out %_pkg.sv, $(wildcard ../../rtl/*/*.sv))
SRCS := ../common/sc_main.cpp ../common/utils.cpp
SRCS_PATH := $(foreach src, $(SRCS), ../../$(src))
PARAMETER_SPEC := ../common/$(DUT).json

TESTS_DIR := tests
TESTS_RUN_DIR := $(TESTS_DIR)/isa
TESTS_RUN_SCRIPT := ../run-tests.py
GEN_MODEL_SCRIPT := ../gen-model.py

.PRECIOUS: %/$(VDUT).json
.PHONY: all sim distclean clean
all: $(VDUTS_OUT) $(TESTS_RUN_DIR)

sim: $(VDUTS_OUT) $(TESTS_RUN_DIR)
	$(TESTS_RUN_SCRIPT) -i "32ui-px-" -e ".dump" -e "fence_i" $(OBJ_DIR) $(TESTS_RUN_DIR)

distclean: clean
	rm -rf $(TESTS_DIR)

clean:
	rm -rf $(OBJ_DIR) *.vcd

%/$(VDUT): %/$(VDUT).mk
	$(MAKE) -C $(@D) -f $(@F).mk $(@F)

%/$(VDUT).mk: %/$(VDUT).json $(SRCS) $(VSRCS) $(DUT_SRC)
	$(VERILATOR) $(CFLAGS) $(VINCLUDE) $(shell $(GEN_MODEL_SCRIPT) -v $<) $(VFLAGS) $(VSRCS) $(DUT_SRC) $(SRCS_PATH) --Mdir $(@D) --prefix $(VDUT)

%/$(VDUT).json: $(PARAMETER_SPEC)
	mkdir -p $(@D)
	$(GEN_MODEL_SCRIPT) -g $< -o $@

$(TESTS_RUN_DIR): $(TESTS_DIR)/Makefile
	$(MAKE) -C $(TESTS_DIR)

$(TESTS_DIR)/Makefile: $(RISCV_ARCH_TESTS)/configure
	mkdir -p $(TESTS_DIR)
	cd $(TESTS_DIR) ; ../$(RISCV_ARCH_TESTS)/configure --prefix=$(shell pwd)/$(TESTS_DIR) ; cd ..

$(RISCV_ARCH_TESTS)/configure:
	git submodule update --init --recursive
