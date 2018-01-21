# ModelSim TCL Simulation Script

set PROJECT wb_sram
set FILES [lsort [glob ../../../rtl/lib/*.sv ../../../rtl/system/*.sv ../../common/*.sv wb_sram_tb.sv]]
set TOP_LEVEL_ENTITY wb_sram_tb

# Create a project if it doesn't exist
if {![file isdirectory $PROJECT]} {
    vlib $PROJECT
    vmap $PROJECT "[exec pwd]/$PROJECT"
}

# Compile the design files
foreach vfile $FILES {
    vlog -sv -work $PROJECT $vfile
}

vsim $PROJECT.$TOP_LEVEL_ENTITY

restart -force -nowave

add wave -r *

run -all

exit
# view wave -undock
# wave zoom full
