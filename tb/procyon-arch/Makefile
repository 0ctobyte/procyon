VERILATOR = verilator
MAKE := make

RISCV_ARCH_TESTS := $(shell echo $(RISCV_ARCH_TESTS))

ifndef TESTS_RUN_DIR
ifeq ($(RISCV_ARCH_TESTS),)
    $(error RISCV_ARCH_TESTS not set)
endif
endif

OBJ_DIR := obj_dir
DUT := dut
CFLAGS := -I../../common
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -Wall -Wno-fatal --trace --sc --exe
VDUT := V$(DUT)
VSRCS :=
SRCS := sc_main.cpp ../common/utils.cpp

TESTS_RUN_DIR := $(RISCV_ARCH_TESTS)
TESTS_RUN_SCRIPT := ./run-tests.py

.PHONY: all sim clean
all: $(OBJ_DIR)/$(VDUT)

sim: $(OBJ_DIR)/$(VDUT)
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)
	$(TESTS_RUN_SCRIPT) $(OBJ_DIR)/$(VDUT) $(TESTS_RUN_DIR)

$(OBJ_DIR)/$(VDUT): $(OBJ_DIR)/$(VDUT).mk
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)

$(OBJ_DIR)/$(VDUT).mk: $(SRCS) $(DUT).sv
	$(VERILATOR) -CFLAGS $(CFLAGS) $(VINCLUDE) $(VSRCS) $(VFLAGS) $(DUT).sv $(SRCS) --prefix $(VDUT)

clean:
	rm -rf $(OBJ_DIR) *.vcd
