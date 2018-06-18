# Quartus tools
QUARTUS_SH := quartus_sh
QUARTUS_PGM := quartus_pgm

# Project configuration
PROJECT := procyon_arch_test
TOP_LEVEL_ENTITY := procyon_arch_test

# Device information
FAMILY := "Cyclone IV E"
DEVICE := EP4CE115F29C7
PIN_ASSIGNMENTS_FILE := de2-115.pin.tcl

# Directory where source files are located
SRCS := $(wildcard ../../rtl/lib/*.sv ../../rtl/system/*.sv ../../rtl/core/*.sv boot_rom.sv procyon_arch_test.sv)

# Load code from hex file
HEX_FILE ?= "tests/rv32ui-u-add.hex"
HEX_SIZE := $(shell wc -l < $(HEX_FILE))

all: $(PROJECT).sof

program: $(PROJECT).sof
	$(QUARTUS_PGM) -m JTAG -o "P;$<"

clean:
	-$(QUARTUS_SH) --clean $(PROJECT)
	rm -rf ${PROJECT}/ transcript modelsim.ini vsim.wlf
	rm -rf db/ $(PROJECT).qsf $(PROJECT).qpf $(PROJECT).tcl

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
	echo "set_global_assignment -name ADD_PASS_THROUGH_LOGIC_TO_INFERRED_RAMS OFF" >> $@
	echo "set_global_assignment -name ALLOW_ANY_RAM_SIZE_FOR_RECOGNITION ON" >> $@
	echo "" >> $@
	echo "# Set HEX_FILE parameter for top-level entity" >> $@
	echo "set_parameter -name HEX_FILE \"$(HEX_FILE)\"" >> $@
	echo "set_parameter -name HEX_SIZE $(HEX_SIZE)" >> $@
	echo "" >> $@
	echo "# Set pin assignments" >> $@
	echo "source \"$(PIN_ASSIGNMENTS_FILE)\"" >> $@
	echo "" >> $@
	echo "# Compile" >> $@
	echo "execute_flow -compile" >> $@
	echo "" >> $@
	echo "project_close" >> $@

$(PROJECT).sof: $(PROJECT).tcl
	$(QUARTUS_SH) --64bit -t $<
