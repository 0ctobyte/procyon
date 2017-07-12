# ModelSim TCL Simulation Script

set PROJECT register_map 
set FILES {../types.sv register_map.sv register_map_tb.sv}
set TOP_LEVEL_ENTITY register_map_tb

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

run 100ns

view wave -undock
wave zoom full
