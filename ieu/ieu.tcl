# ModelSim TCL Simulation Script

set PROJECT ieu
set FILES {../types.sv ieu_tb.sv ieu.sv ieu_id.sv ieu_ex.sv ../reservation_station/reservation_station.sv ../dp_ram/dp_ram.sv ../sync_fifo/sync_fifo.sv ../dispatch/dispatch.sv ../reorder_buffer/reorder_buffer.sv ../register_map/register_map.sv}
set TOP_LEVEL_ENTITY ieu_tb

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

run 1000ns

view wave -undock
wave zoom full
