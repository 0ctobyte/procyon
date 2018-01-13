PROJECT := wb_sram
VSIM_OPTS := -c

ifneq ($(strip $(GUI)),)
    VSIM_OPTS =
endif

all: ${PROJECT}.tcl
	vsim $(VSIM_OPTS) -do $<

clean:
	rm -rf ${PROJECT}/ transcript modelsim.ini vsim.wlf
