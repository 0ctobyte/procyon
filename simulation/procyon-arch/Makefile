VERILATOR = verilator
MAKE := make

OBJ_DIR := obj_dir
DUT := dut
CFLAGS := -I../../common
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -Wall -Wno-fatal --trace --sc --exe
VDUT := V$(DUT)
VSRCS := procyon_types.sv
SRCS := sc_main.cpp ../common/utils.cpp ../common/BootRom.cpp ../common/Sram.cpp

TESTS_RUN_DIR := tests
TESTS_RUN_SCRIPT := ./run_tests.py

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
