# ModelSim TCL Simulation Script

set PROJECT reorder_buffer 
set FILES {../types.sv reorder_buffer.sv reorder_buffer_tb.sv}
set TOP_LEVEL_ENTITY reorder_buffer_tb

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

add wave -R *

force clk 1 0ns, 0 5ns -repeat 10ns
force n_rst 0 0ns, 1 10ns

run 100ns

view wave -undock
wave zoom full
