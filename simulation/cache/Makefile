VERILATOR = verilator
MAKE := make

OBJ_DIR := obj_dir
DUT := dut
CFLAGS := -I../../common
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -Wall -Wno-fatal --trace --sc --exe
VDUT := V$(DUT)
SRCS := sc_main.cpp ../common/Sram.cpp ../common/WBBusInterfaceUnit.cpp Driver.cpp Monitor.cpp

.PHONY: all sim clean
all: $(OBJ_DIR)/$(VDUT)

sim: $(OBJ_DIR)/$(VDUT)
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)
	$(OBJ_DIR)/$(VDUT)

$(OBJ_DIR)/$(VDUT): $(OBJ_DIR)/$(VDUT).mk
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)

$(OBJ_DIR)/$(VDUT).mk: $(SRCS) $(DUT).sv
	$(VERILATOR) -CFLAGS $(CFLAGS) $(VINCLUDE) $(VFLAGS) $(DUT).sv $(SRCS)

clean:
	rm -rf $(OBJ_DIR) *.vcd
