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

# Directory where source files are located
SRCS := $(wildcard ../../rtl/lib/*.sv ../../rtl/system/*.sv ../../rtl/core/*.sv ../common/*.sv procyon_sys_top.sv)

RISCV_ARCH_TESTS := ../../riscv-tests

# Load code from hex file
TESTS_DIR := tests
HEX_DIR := $(TESTS_DIR)/isa
PROGRAM ?= rv32ui-px-add
HEX_FILE := $(HEX_DIR)/$(PROGRAM).hex
HEXIFY_SCRIPT := ../hexify-bin.py

IC_LINE_SIZE ?= 32

.PHONY: all program clean distclean
all: $(HEX_FILE) $(PROJECT).sof

program: $(HEX_FILE) $(PROJECT).sof
	$(QUARTUS_PGM) -m JTAG -o "P;$<"

distclean: clean
	rm -rf $(TESTS_DIR)

clean:
	-$(QUARTUS_SH) --clean $(PROJECT)
	rm -rf ${PROJECT}/ transcript modelsim.ini vsim.wlf *.hex
	rm -rf db/ $(PROJECT).qsf $(PROJECT).qpf $(PROJECT).tcl
	-rm $(HEX_DIR)/*.hex

$(HEX_FILE): $(HEX_DIR)
	$(HEXIFY_SCRIPT) -e ".dump" -e ".hex" -w $(IC_LINE_SIZE) $(HEX_DIR) $(HEX_DIR)

$(HEX_DIR): $(TESTS_DIR)/Makefile
	$(MAKE) -C $(TESTS_DIR)

$(TESTS_DIR)/Makefile: $(RISCV_ARCH_TESTS)/configure
	mkdir -p $(TESTS_DIR)
	cd $(TESTS_DIR) ; ../$(RISCV_ARCH_TESTS)/configure --prefix=$(shell pwd)/$(TESTS_DIR) ; cd ..

$(RISCV_ARCH_TESTS)/configure:
	git submodule update --init --recursive

$(PROJECT).sof: $(PROJECT).tcl
	$(QUARTUS_SH) --64bit -t $<

$(PROJECT).tcl: $(PIN_ASSIGNMENTS_FILE)
	echo "# Load Quartus Prime Tcl project package" >> $@
	echo "package require ::quartus::project" >> $@
	echo "" >> $@
	echo "# Load flow package" >> $@
	echo "load_package flow" >> $@
	echo "" >> $@
	echo "# Create project" >> $@
	echo "project_new $(PROJECT) -revision $(PROJECT) -overwrite" >> $@
	echo "" >> $@
	echo "# Set project user libraries" >> $@
	$(foreach SRC,$(SRCS),echo "set_global_assignment -name SYSTEMVERILOG_FILE $(SRC)" >> $@;)
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
	echo "set_parameter -name OPTN_HEX_SIZE $(shell wc -l < $(HEX_FILE) | xargs expr 1 +)" >> $@
	echo "set_parameter -name OPTN_IC_LINE_SIZE \"$(IC_LINE_SIZE)\"" >> $@
	echo "" >> $@
	echo "# Set pin assignments" >> $@
	echo "source \"$(PIN_ASSIGNMENTS_FILE)\"" >> $@
	echo "" >> $@
	echo "# Compile" >> $@
	echo "execute_flow -compile" >> $@
	echo "" >> $@
	echo "project_close" >> $@
