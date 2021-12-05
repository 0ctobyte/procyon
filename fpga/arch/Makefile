# Quartus tools
QUARTUS_SH := quartus_sh
QUARTUS_PGM := quartus_pgm

# Project configuration
PROJECT := procyon_sys_top
TOP_LEVEL_ENTITY := procyon_sys_top

# Device information
FAMILY := "Cyclone IV E"
DEVICE := EP4CE115F29C7
PIN_ASSIGNMENTS_FILE := ../common/de2-115.pin.tcl

VERILATOR = verilator
MAKE := make

RISCV_ARCH_TESTS := ../../riscv-tests

# Load code from hex file
TESTS_DIR := tests
TESTS_ISA_DIR := tests/isa
HEX_DIR := hex
PROGRAM ?= rv32ui-px-add
HEX_FILE := $(HEX_DIR)/$(PROGRAM).hex
HEXIFY_SCRIPT := ../hexify-bin.py

IC_LINE_SIZE ?= 32

OBJ_DIR := obj_dir
DUT := dut
DUT_SRC := ../common/$(DUT).sv
CFLAGS := -CFLAGS -I../../../tb/common -I../../common -CFLAGS -DIC_LINE_SIZE=$(IC_LINE_SIZE)
VINCLUDE := -I../../rtl/core -I../../rtl/lib -I../../rtl/system -I../common
VFLAGS := -GOPTN_IC_LINE_SIZE=$(IC_LINE_SIZE) -GOPTN_HEX_FILE=\"$(HEX_FILE)\" -Wall -Wno-fatal --trace --sc --exe
VDUT := V$(DUT)
VSRCS := $(wildcard ../../rtl/*/*.sv ../common/*.sv)
SRCS := sc_main.cpp ../../tb/common/utils.cpp

# Check if the tcl file contains the right hex file in case the HEX_FILE variable has been updated via a make call
# specifying a new PROGRAM. The touch command will force make to re-write the tcl file and re-build the FPGA bitstream
# using the new hex file
ifneq ("$(wildcard $(PROJECT).tcl)", "")
    ifneq ("$(wildcard $(HEX_FILE))", "")
        ifeq ("$(shell grep $(HEX_FILE) $(PROJECT).tcl)", "")
            $(shell touch $(HEX_FILE))
        endif
    endif
endif

.PHONY: all program clean distclean
all: $(PROJECT).sof

sim: $(HEX_FILE) $(OBJ_DIR)/$(VDUT)
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)
	$(OBJ_DIR)/$(VDUT)

program: $(PROJECT).sof
	$(QUARTUS_PGM) -m JTAG -o "P;$<"

distclean: clean
	-rm -rf $(TESTS_DIR)

clean:
	-$(QUARTUS_SH) --clean $(PROJECT)
	-rm -rf ${PROJECT}/ transcript modelsim.ini vsim.wlf *.hex
	-rm -rf db/ $(PROJECT).qsf $(PROJECT).qpf $(PROJECT).tcl
	-rm -rf $(HEX_DIR)
	-rm -rf $(OBJ_DIR) *.vcd

$(PROJECT).sof: $(PROJECT).tcl
	$(QUARTUS_SH) --64bit -t $<

$(PROJECT).tcl: $(PIN_ASSIGNMENTS_FILE) $(VSRCS) $(HEX_FILE)
	echo "# Load Quartus Prime Tcl project package" > $@
	echo "package require ::quartus::project" >> $@
	echo "" >> $@
	echo "# Load flow package" >> $@
	echo "load_package flow" >> $@
	echo "" >> $@
	echo "# Create project" >> $@
	echo "project_new $(PROJECT) -revision $(PROJECT) -overwrite" >> $@
	echo "" >> $@
	echo "# Set project user libraries" >> $@
	$(foreach VSRC,$(VSRCS),echo "set_global_assignment -name SYSTEMVERILOG_FILE $(VSRC)" >> $@;)
	echo "" >> $@
	echo "# Set global assignments" >> $@
	echo "set_global_assignment -name FAMILY \"$(FAMILY)\"" >> $@
	echo "set_global_assignment -name DEVICE $(DEVICE)" >> $@
	echo "set_global_assignment -name TOP_LEVEL_ENTITY $(TOP_LEVEL_ENTITY)" >> $@
	# echo "set_global_assignment -name ADD_PASS_THROUGH_LOGIC_TO_INFERRED_RAMS OFF" >> $@
	echo "set_global_assignment -name ALLOW_ANY_RAM_SIZE_FOR_RECOGNITION ON" >> $@
	echo "" >> $@
	echo "# Set HEX_FILE parameter for top-level entity" >> $@
	echo "set_parameter -name OPTN_HEX_FILE \"$(HEX_FILE)\"" >> $@
	echo "set_parameter -name OPTN_HEX_SIZE $(shell wc -l < $(HEX_FILE))" >> $@
	echo "set_parameter -name OPTN_IC_LINE_SIZE \"$(IC_LINE_SIZE)\"" >> $@
	echo "" >> $@
	echo "# Set pin assignments" >> $@
	echo "source \"$(PIN_ASSIGNMENTS_FILE)\"" >> $@
	echo "" >> $@
	echo "# Compile" >> $@
	echo "execute_flow -compile" >> $@
	echo "" >> $@
	echo "project_close" >> $@

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

$(OBJ_DIR)/$(VDUT): $(OBJ_DIR)/$(VDUT).mk
	$(MAKE) -C $(OBJ_DIR) -f $(VDUT).mk $(VDUT)

$(OBJ_DIR)/$(VDUT).mk: $(SRCS) $(VSRCS) $(DUT_SRC)
	$(VERILATOR) $(CFLAGS) $(VINCLUDE) -GOPTN_HEX_SIZE=$(shell wc -l < $(HEX_FILE)) $(VFLAGS) $(DUT_SRC) $(SRCS) --prefix $(VDUT)
