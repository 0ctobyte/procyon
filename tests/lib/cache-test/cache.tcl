# ModelSim TCL Simulation Script

set PROJECT cache
set FILES [lsort [glob ../../../rtl/lib/*.sv ../../../rtl/system/*.sv ../../common/*.sv cache_driver.sv cache_tb.sv]]
set TOP_LEVEL_ENTITY cache_tb

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
