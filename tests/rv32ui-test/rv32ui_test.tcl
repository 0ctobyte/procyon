# ModelSim TCL Simulation Script

set PROJECT rv32ui_test
set FILES {../../rtl/types.sv rv32ui_test_tb.sv ../../rtl/fetch.sv ../../rtl/ieu.sv ../../rtl/ieu_id.sv ../../rtl/ieu_ex.sv ../../rtl/reservation_station.sv ../../rtl/lib/dp_ram.sv ../../rtl/lib/sync_fifo.sv ../../rtl/dispatch.sv ../../rtl/reorder_buffer.sv ../../rtl/register_map.sv ../../rtl/lib/rom.sv}
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

log -r * /register_map_inst/regmap

run -all

exit
# view wave -undock
# wave zoom full
