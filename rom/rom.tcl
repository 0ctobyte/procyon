# ModelSim TCL Simulation Script

set PROJECT rom
set FILES {rom.sv rom_tb.sv ../types.sv}
set TOP_LEVEL_ENTITY rom_tb

# Create a project if it doesn't exist
if {![file isdirectory $PROJECT]} {
    vlib $PROJECT
    vmap $PROJECT "[exec pwd]/$PROJECT"
}

# Compile the design files
foreach vfile $FILES {
    vlog -work $PROJECT $vfile
}

vsim $PROJECT.$TOP_LEVEL_ENTITY

restart -force -nowave

add wave -r *

force clk 1 0ns, 0 10ns -repeat 20ns
force n_rst 0 0ns, 1 20ns

force {i_rd_addr} 0 0ns, 16#1 40ns, 16#2 60ns, 16#3 80ns

run 100ns

view wave -undock
wave zoom full
