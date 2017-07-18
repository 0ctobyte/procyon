# ModelSim TCL Simulation Script

set PROJECT dispatch
set FILES {../types.sv dispatch.sv dispatch_tb.sv ../dp_ram/dp_ram.sv ../sync_fifo/sync_fifo.sv ../reorder_buffer/reorder_buffer.sv ../register_map/register_map.sv}
set TOP_LEVEL_ENTITY dispatch_tb

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

add wave -r * /register_map_inst/regmap

run 100ns

view wave -undock
wave zoom full
