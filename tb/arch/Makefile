VERILATOR = verilator
MAKE := make

RISCV_ARCH_TESTS := ../../riscv-tests

OBJ_DIR := obj_dir
DUT := dut
DUT_SRC := ../common/$(DUT).sv
CFLAGS := -CFLAGS -I../../common
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -Wall -Wno-fatal --trace --top-module $(DUT) --sc --exe
VDUT := V$(DUT)
VSRCS := ../../rtl/lib/procyon_lib_pkg.sv ../../rtl/system/procyon_system_pkg.sv ../../rtl/core/procyon_core_pkg.sv $(filter-out %_pkg.sv, $(wildcard ../../rtl/*/*.sv))
SRCS := ../common/sc_main.cpp ../common/utils.cpp

TESTS_DIR := tests
TESTS_RUN_DIR := $(TESTS_DIR)/isa
TESTS_RUN_SCRIPT := ../run-tests.py

.PHONY: all sim distclean clean
all: $(OBJ_DIR)/$(VDUT) $(TESTS_RUN_DIR)

sim: $(OBJ_DIR)/$(VDUT) $(TESTS_RUN_DIR)
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)
	$(TESTS_RUN_SCRIPT) -i "32ui-px-" -e ".dump" $(OBJ_DIR)/$(VDUT) $(TESTS_RUN_DIR)

distclean: clean
	rm -rf $(TESTS_DIR)

clean:
	rm -rf $(OBJ_DIR) *.vcd

$(OBJ_DIR)/$(VDUT): $(OBJ_DIR)/$(VDUT).mk
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)

$(OBJ_DIR)/$(VDUT).mk: $(SRCS) $(VSRCS) $(DUT_SRC)
	$(VERILATOR) $(CFLAGS) $(VINCLUDE) $(VFLAGS) $(VSRCS) $(DUT_SRC) $(SRCS) --prefix $(VDUT)

$(TESTS_RUN_DIR): $(TESTS_DIR)/Makefile
	$(MAKE) -C $(TESTS_DIR)

$(TESTS_DIR)/Makefile: $(RISCV_ARCH_TESTS)/configure
	mkdir -p $(TESTS_DIR)
	cd $(TESTS_DIR) ; ../$(RISCV_ARCH_TESTS)/configure --prefix=$(shell pwd)/$(TESTS_DIR) ; cd ..

$(RISCV_ARCH_TESTS)/configure:
	git submodule update --init --recursive
