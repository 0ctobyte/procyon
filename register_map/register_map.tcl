# ModelSim TCL Simulation Script

set PROJECT register_map 
set FILES register_map.sv
set TOP_LEVEL_ENTITY register_map

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

add wave *

force clk 1 0ns, 0 5ns -repeat 10ns
force n_rst 0 0ns, 1 10ns

run 100ns

view wave -undock
wave zoom full
