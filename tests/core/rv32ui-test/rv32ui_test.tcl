# ModelSim TCL Simulation Script

set PROJECT rv32ui_test
set FILES [lsort [glob ../../../rtl/lib/*.sv ../../../rtl/core/*.sv rv32ui_test_tb.sv]]
set TOP_LEVEL_ENTITY rv32ui_test_tb

# Create a project if it doesn't exist
if {![file isdirectory $PROJECT]} {
    vlib $PROJECT
    vmap $PROJECT "[exec pwd]/$PROJECT"
}

# Compile the design files
foreach vfile $FILES {
    vlog -sv -work $PROJECT $vfile
}

vsim -GROM_FILE=$1 $PROJECT.$TOP_LEVEL_ENTITY

restart -force -nowave

add wave -r * /register_map_inst/regmap

run -all

# exit
# view wave -undock
# wave zoom full
