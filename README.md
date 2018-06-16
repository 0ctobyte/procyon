# Procyon
*Procyon is the brightest star in the constellation of Canis Minor*

Procyon is a dynamically scheduling, scalar, speculative RISCV processor. The hardware is implemented in SystemVerilog and simulated in SystemC using Verilator to translate the SystemVerilog modules to C++.

# Running Simulations

In the `simulation` directory there are several simulation tests:

* `procyon-arch`: RISCV CPU architectural tests
* `cache`: Cache simulation
* `wb-sram`: Wishbone SRAM slave module simulation

Running `make sim` in each directory will build and run the simulation. For `procyon-arch` this will run a suite of rv32ui architectural tests in `procyon-arch/tests` (precompiled from the [riscv-tests](https://github.com/riscv/riscv-tests) repo with some special tweaks). It's also possible to run an arbitrary free-standing baremetal binary. From the `procyon-arch` directory:

`make`
`obj_dir/Vdut <binary>`

# FPGA Build

In the `fpga` directory there are several fpga tests similar to the simulation tests. Currently, only the CycloneIVe FPGA on the Terasic DE2-115 board is supported. To build run `make`. To program the FPGA run `make program`.

The Procyon core and system is functional on the FPGA with the following blocks:

* `procyon`: The actual RISCV core
* `bootrom`: Interfaces with the fetch unit in the core. This is loaded with a freestanding baremetal binary converted to .hex format
* `wb_sram`: Wishbone SRAM slave module used to interface with the SRAM chip on the DE2-115 board and connected to the Wishbone bus

To convert a binary to .hex format use the `hexify-bin.py` script in the `fpga/procyon-arch` directory: `hexify-bin.py <binary`
To build the FPGA bitstream with a custom binary loaded into the bootrom: `make HEX_FILE=<hex_file>`

# The Procyon Core

The Procyon core is an out-of-order, speculative processor. At a high-level the processor has 6 stages:

Stage | Description  
----- | -----------  
Fetch | Retrieve an instruction from the instruction cache/bootrom and place it into the Instruction FIFO  
Dispatch | Decode an instruction from the Instruction FIFO every cycle and reserve entries in the Reorder Buffer and the appropriate Reservation Station depending on the instruction type  
Issue | When all operands are available an instruction can be issued into the appropriate functional unit every cycle  
Execute | Execute the instruction, this may take one or more cycles. The functional units are pipelined so they can be executing multiple instructions in different stages simultaneously  
Complete | Broadcast the result on the CDB (Common Data Bus) which will feed into each Reservation Station to provide dependent instructions with the operands they may be waiting for and mark the entry as completed in the Reorder Buffer  
Retire | Once the instruction reaches the head of the Reorder Buffer and the instruction has been completed it will be retired which means it will be removed from the Reorder Buffer and the result value (if any) written into the Register File  

Currently, there are two functional units:

###### LSU: Load Store Unit

Processes loads and stores and interfaces with the Data Cache and the Miss Handling Queue. Loads are kept in the Load Queue until they are retired from the Reorder Buffer. Mis-speculated loads are detected every time a store is retired. When loads are retired they will signal to the Reorder Buffer that the load has been mis-speculated in which case the Reorder Buffer will signal to the Fetch Unit to restart fetching from the load instruction and flush the pipeline. Stores are kept in the Store Queue and are not written out to the Data Cache or Miss Handling Queue (if it misses in the Data Cache) until they are retired. Loads that miss in the cache are enqueued in the Miss Handling Queue and the are marked as "needing replay" and tagged with the Miss Handling Queue entry number in the Load Queue. When the Miss Handling Queue services the miss request, it will signal to the Load Queue with the tag and any load waiting on that tag will be replayed.

###### IEU: Integer Execution Unit

Processes integer instructions including jump and branch instructions. Jump and branch instructions that are determined to be taken will signal to the Reorder Buffer the branch address and that the branch is "valid". The Reorder Buffer will then signal to the Fetch Unit to perform the branch/jump when the branch/jump instruction is retired (this will cause a pipeline/Reorder Buffer flush).

# The Procyon System
