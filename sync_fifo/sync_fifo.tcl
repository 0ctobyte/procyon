# ModelSim TCL Simulation Script

set PROJECT sync_fifo 
set FILES {../dp_ram/dp_ram.sv sync_fifo.sv sync_fifo_tb.sv ../types.sv}
set TOP_LEVEL_ENTITY sync_fifo_tb

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

force clk 1 0ns, 0 5ns -repeat 10ns
force n_rst 0 0ns, 1 10ns

force {if_fifo_wr.wr_en} 0 0ns, 1 10ns, 0 90ns, 1 180ns, 0 260ns
force {if_fifo_wr.data_in} 0 0ns, 0x12 10ns, 0x32 20ns, 0x43 30ns, 0x54 40ns, 0x65 50ns, 0x76 60ns, 0x87 70ns, 0x98 80ns, 0xa9 180ns, 0xba 190ns, 0xcb 200ns, 0xdc 210ns, 0xed 220ns, 0xfe 230ns, 0x0f 240ns, 0x10 250ns

force {if_fifo_rd.rd_en} 0 0ns, 1 91ns

force i_flush 0 0ns, 1 40ns, 0 50ns

run 400ns

view wave -undock
wave zoom full
