include ../common/common.mk

TESTS_ISA_DIR := tests/isa

# RISCV architecture test code submodule
RISCV_ARCH_TESTS := ../../riscv-tests

$(HEX_FILE): $(TESTS_ISA_DIR)/$(PROGRAM)
	mkdir -p $(HEX_DIR)
	$(HEXIFY_SCRIPT) -e ".dump" -e ".hex" -w $(IC_LINE_SIZE) $< $(HEX_DIR)

$(TESTS_ISA_DIR)/$(PROGRAM): $(TESTS_DIR)/Makefile
	$(MAKE) -C $(TESTS_DIR)

$(TESTS_DIR)/Makefile: $(RISCV_ARCH_TESTS)/configure
	mkdir -p $(TESTS_DIR)
	cd $(TESTS_DIR) ; ../$(RISCV_ARCH_TESTS)/configure --prefix=$(shell pwd)/$(TESTS_DIR) ; cd ..

$(RISCV_ARCH_TESTS)/configure:
	git submodule update --init --recursive
