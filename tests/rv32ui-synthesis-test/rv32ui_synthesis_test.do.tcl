# ModelSim TCL Simulation Script

set PROJECT rv32ui_synthesis_test
set FILES {../../rtl/types.sv rv32ui_synthesis_test.sv simple_fetch.sv ../../rtl/ieu.sv ../../rtl/ieu_id.sv ../../rtl/ieu_ex.sv ../../rtl/reservation_station.sv ../../rtl/lib/dp_ram.sv ../../rtl/lib/sync_fifo.sv ../../rtl/dispatch.sv ../../rtl/reorder_buffer.sv ../../rtl/register_map.sv ../../rtl/lib/rom.sv seg7_decoder.sv edge_detector.sv synchronizer.sv}
set TOP_LEVEL_ENTITY rv32ui_synthesis_test

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

force CLOCK_50 1 0ns, 0 10ns -repeat 20ns
force {SW[17]} 0 0ns, 1 10ns

force {KEY[0]} 1 0ns, 0 80ns -repeat 120ns

run 1000ns

view wave -undock
wave zoom full
