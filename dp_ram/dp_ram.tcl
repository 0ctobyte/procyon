# ModelSim TCL Simulation Script

set PROJECT dp_ram
set FILES {dp_ram.sv dp_ram_tb.sv ../types.sv}
set TOP_LEVEL_ENTITY dp_ram_tb

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

force {if_dp_ram.data_in} 0 0ns, 16#be 20ns, 16#ef 60ns
force {if_dp_ram.wr_addr} 0 0ns, 16#1 20ns, 16#7 60ns
force {if_dp_ram.wr_en} 0 0ns, 1 20ns, 0 40ns, 1 60ns

force {if_dp_ram.rd_addr} 0 0ns, 16#1 40ns, 16#7 60ns
force {if_dp_ram.rd_en} 0 0ns, 1 40ns, 1 60ns, 1 80ns

run 100ns

view wave -undock
wave zoom full
