.DEFAULT_GOAL := sim

include ../common/common.mk

TESTS_RUN_DIR := $(TESTS_DIR)/isa

# RISCV architecture test code submodule
RISCV_ARCH_TESTS := ../../riscv-tests

.PHONY: build-only sim
build-only: $(VDUTS_OUT) $(TESTS_RUN_DIR)

sim: $(VDUTS_OUT) $(TESTS_RUN_DIR)
	$(TESTS_RUN_SCRIPT) -i "32ui-px-" -e ".dump" -e "fence_i" $(OBJ_DIR) $(TESTS_RUN_DIR)

$(TESTS_RUN_DIR): $(TESTS_DIR)/Makefile
	$(MAKE) -C $(TESTS_DIR)

$(TESTS_DIR)/Makefile: $(RISCV_ARCH_TESTS)/configure
	$(MKDIR) -p $(TESTS_DIR)
	cd $(TESTS_DIR) ; ../$(RISCV_ARCH_TESTS)/configure --prefix=$(shell pwd)/$(TESTS_DIR) ; cd ..

$(RISCV_ARCH_TESTS)/configure:
	git submodule update --init --recursive
