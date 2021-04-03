# Procyon
*Procyon is the brightest star in the constellation of Canis Minor*

Procyon is a dynamically scheduling, scalar, speculative RISCV processor. The hardware is implemented in SystemVerilog and simulated in SystemC using Verilator. There is also a bitstream target for the CycloneIVe FPGA on the Terasic DE2-115 board.

# Running Simulations

In the `tb` directory there are some tests:

* `procyon-arch`: RISCV CPU architectural tests
* `wb-sram`: Wishbone SRAM slave module simulation

Running `make sim` in each directory will build and run the simulation. For `procyon-arch` this will run a suite of rv32ui architectural tests in `procyon-arch/tests` (precompiled from the [riscv-tests](https://github.com/riscv/riscv-tests) repo with some special tweaks). It's also possible to run an arbitrary free-standing baremetal binary. From the `procyon-arch` directory:

`make`

`obj_dir/Vdut <binary>`

# FPGA Build

In the `fpga` directory there are several fpga tests similar to the simulation tests. Currently, only the CycloneIVe FPGA on the Terasic DE2-115 board is supported. To build run `make`. To program the FPGA run `make program`.

The Procyon core and system is functional on the FPGA with the following blocks:

* `procyon`: The actual RISCV core
* `bootrom`: Interfaces with the fetch unit in the core. This is loaded with a freestanding baremetal binary converted to .hex format
* `wb_sram`: Wishbone SRAM slave module used to interface with the IS61WV102416BLL SRAM chip on the DE2-115 board and connected to the Wishbone bus

To convert a binary to .hex format use the `hexify-bin.py` script in the `fpga/procyon-arch` directory: `hexify-bin.py <binary>`
To build the FPGA bitstream with a custom binary loaded into the bootrom: `make HEX_FILE=<hex_file>`

# The Procyon Core

![Procyon uArchitecture Diagram](https://raw.githubusercontent.com/0ctobyte/procyon/master/Procyon-Core.png)

The Procyon core is an out-of-order, speculative processor. At a high-level an instruction goes through the following stages in the processor:

Stage | Description
----- | -----------
Fetch | Retrieve an instruction from the instruction cache and place it into the Instruction FIFO
Dispatch | Partially decode an instruction from the Instruction FIFO every cycle and reserve entries in the Reorder Buffer and the appropriate Reservation Station depending on the instruction type. Gets values or producer of source registers and renames destination registers in the register map
Issue | When all operands are available an instruction can be issued into the appropriate functional unit every cycle. The reservation station will capture register values from produce ops and schedule ready instructions to it's functional unit when available
Execute | Execute the instruction, this may take one or more cycles. The functional units are pipelined so they can be executing multiple instructions in different stages simultaneously. Loads will speculatively load from the data cache regardless of outstanding stores. Stores will just generate the effective address and wait in the store queue until it can be retired.
Complete | Broadcast the result on the CDB (Common Data Bus) which will feed into each Reservation Station to provide dependent instructions with the operands they may be waiting for and mark the entry as completed in the Reorder Buffer. Loads that miss in the data cache will wait in the load queue until the data is available at which point the load will be retried. Stores will let the reorder buffer know that it's ready to be retired but will not update the cache.
Retire | Once the instruction reaches the head of the Reorder Buffer and the instruction has been completed it will be retired which means it will be removed from the Reorder Buffer and the result value (if any) written into the Register File. For stores, the reorder buffer will signal the store queue to retire the store. The store queue will, as soon as the next cycle, tell the LSU to write the store data to the cache. If the store misses in the cache it will wait in the store queue until the cacheline is available. At this point the stores will CAM the load queue and mark any load to the same address bytes as invalid.

At a finer level, the processor's pipeline is organized as described below for the various execution paths.

## Front-End Pipeline

![Procyon Front-End Pipeline Diagram](https://raw.githubusercontent.com/0ctobyte/procyon/master/Procyon-Core-FE-Pipeline.jpeg)

This part of the pipeline is the same for all instructions both ALU, branch and load/store instructions. It's composed of the Fetch and Dispatch stages. The dispatch stage is split into two cycles as described below

### Fetch Stage

The fetch stage is very simple at the moment. It simply takes the current PC and retrieves the instruction word from the bootrom. There is no instruction cache, address translation or branch prediction implemented at the moment. The PC is incremented by 4 for the next fetch.

### Dispatch Stage

#### Decode & Rename

#### Map & Dispatch

## IEU Pipeline

![Procyon IEU Pipeline Diagram](https://raw.githubusercontent.com/0ctobyte/procyon/master/Procyon-Core-IEU-Pipeline.jpeg)

The IEU (Integer Execution Unit) decodes and executes all ALU and branch instructions in the execution stage of the pipeline. It is split into two cycles.

### IEU: Integer Execution Unit

#### Instruction Decode

#### Execute

## LSU Pipeline

![Procyon LSU Pipeline Diagram](https://raw.githubusercontent.com/0ctobyte/procyon/master/Procyon-Core-LSU-Pipeline.jpeg)

The load/store unit performs loads and stores in the execution stage. The main pipeline is split into four cycles but is complicated by the fact of data cache misses and structural hazards due to cache fills, older loads/stores replaying or stores retiring.

### LSU: Load/Store Unit

#### Instruction Decode & Address Generation

#### DCache Data/Tag Read

#### DCache Hit Check & Write

#### Execute

#### Store Retire

#### Load/Store Replay

### MHQ: Miss Handling Queue

#### MHQ Lookup

#### MHQ Execute

#### Cache Fills