PROJECT := rv32ui_test
DO_TEST := do_rv32ui_tests.tcl
TEST_FILE ?= tests/rv32ui-p-add.hex
VSIM_OPTS := -c

ifneq ($(strip $(GUI)),)
    VSIM_OPTS =
endif

all: ${DO_TEST}
	vsim $(VSIM_OPTS) -do "do $<"

test: ${PROJECT}.tcl
	vsim $(VSIM_OPTS) -do "do $< ${TEST_FILE}"

clean:
	rm -rf ${PROJECT}/ transcript modelsim.ini vsim.wlf
