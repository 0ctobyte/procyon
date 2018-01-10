PROJECT := rv32ui_test
TEST_FILE ?= rv32ui-p-add.hex

all: ${PROJECT}.tcl ${TEST_FILE}
	vsim -c -do "do $< ${TEST_FILE}"

clean:
	rm -rf ${PROJECT}/ transcript modelsim.ini vsim.wlf 
