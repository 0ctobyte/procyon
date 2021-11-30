VERILATOR = verilator
MAKE := make

RISCV_ARCH_TESTS := ../../riscv-tests

IC_LINE_SIZE ?= 32

OBJ_DIR := obj_dir
DUT := dut
CFLAGS := -CFLAGS -I../../common -CFLAGS -DIC_LINE_SIZE=$(IC_LINE_SIZE)
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -GOPTN_IC_LINE_SIZE=$(IC_LINE_SIZE) -Wall -Wno-fatal --trace --sc --exe
VDUT := V$(DUT)
VSRCS :=
SRCS := sc_main.cpp ../common/utils.cpp

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

$(OBJ_DIR)/$(VDUT).mk: $(SRCS) $(DUT).sv
	$(VERILATOR) $(CFLAGS) $(VINCLUDE) $(VSRCS) $(VFLAGS) $(DUT).sv $(SRCS) --prefix $(VDUT)

$(TESTS_RUN_DIR): $(TESTS_DIR)/Makefile
	$(MAKE) -C $(TESTS_DIR)

$(TESTS_DIR)/Makefile: $(RISCV_ARCH_TESTS)/configure
	mkdir -p $(TESTS_DIR)
	cd $(TESTS_DIR) ; ../$(RISCV_ARCH_TESTS)/configure --prefix=$(shell pwd)/$(TESTS_DIR) ; cd ..

$(RISCV_ARCH_TESTS)/configure:
	git submodule update --init --recursive
