# Procyon
*Procyon is the brightest star in the constellation of Canis Minor*

Procyon is a dynamically scheduling, scalar, speculative RISCV processor supporting the RV32I ISA. here are some of the key features for this processor:

* Highly parameterizable
* Synthesizes for FPGAs
* Out-of-order execution
* Non-blocking L1 data cache with configurable number of outstanding misses
* Speculative execution across branches and speculative load execution with memory disambiguation
* Configurable number of integer issue pipelines
* Wishbone bus interface

The hardware is implemented in SystemVerilog and simulated in SystemC using Verilator. There is also a bitstream target for the CycloneIVe FPGA on the Terasic DE2-115 board.

# Running Simulations

In the `tb` directory there are some tests:

* `arch`: RISCV CPU architectural tests
* `lsu`: Tests that stress the LSU in various ways

Running `make sim` in each directory will build and run the simulation. For `arch` this will run a suite of rv32ui architectural tests. The architectural tests' source code can be found at [riscv-tests](https://github.com/0ctobyte/riscv-tests) which is a submodule in this repo. The `riscv-tests` repo is a fork of the official [riscv-tests](https://github.com/riscv/riscv-tests) repo with some special tweaks to get the tests running on procyon. It's also possible to run an arbitrary free-standing bare-metal binary. From the `arch` directory:

`make`

`obj_dir/Vdut <binary>`

The above will also work from any of the other directories in the `tb` directory.

# FPGA Build

In the `fpga` directory there are several FPGA tests similar to the simulation tests. Currently, only the CycloneIVe FPGA on the Terasic DE2-115 board is supported. To build run `make`. To program the FPGA run `make program`.

The Procyon core and system is functional on the FPGA with the following blocks:

* `procyon`: The actual RISCV core
* `bootrom`: Interfaces with the fetch unit in the core. This is loaded with a freestanding bare-metal binary converted to .hex format
* `wb_sram`: Wishbone SRAM slave module used to interface with the IS61WV102416BLL SRAM chip on the DE2-115 board and connected to the Wishbone bus

A python script, `hexify-bin.py`, is provided to convert an elf or binary file to .hex format: `hexify-bin.py <binary> <out_dir>`. This is used by the Makefile automatically.

To build the FPGA bitstream with a custom binary loaded into the bootrom: `make PROG_FILE=<riscv_program>`.
The `RISCV_ARCH_TESTS` environment variable must be set to the directory containing the riscv elf/binary file or it can be overridden by providing `PROG_DIR=<dir>` to the `make` command.

# The Procyon Core

![Procyon uArchitecture Diagram](https://raw.githubusercontent.com/0ctobyte/procyon/master/Procyon-Core.png)

The Procyon core is an out-of-order, speculative processor. At a high-level an instruction goes through the following stages in the processor:

Stage | Description
----- | -----------
Fetch | Retrieve an instruction from the instruction cache and place it into the Instruction FIFO.
Decode | Decodes an instruction from the Instruction FIFO every cycle and reserve entries in the Reorder Buffer and the appropriate Reservation Station depending on the instruction type. Gets values or producer of source registers and renames destination registers in the Register Alias Table.
Dispatch | Updates entries in the Reorder Buffer and Reservation Station for the new instruction and allows it to be scheduled when it's ready.
Issue | When all operands are available an instruction can be issued into the appropriate functional unit every cycle. The reservation station will capture register values from producer ops and schedule ready instructions to it's functional unit when available.
Execute | Execute the instruction, this may take one or more cycles. The functional units are pipelined so they can be executing multiple instructions in different pipeline cycles simultaneously. Loads will speculatively load from the data cache regardless of outstanding stores. Stores will just generate the effective address and wait in the store queue until it can be retired.
Complete | Broadcast the result on the Common Data Bus (CDB) which will feed into each Reservation Station to provide dependent instructions with the operands that they may be waiting for and mark the instruction as completed in the Reorder Buffer. Loads that miss in the data cache will wait in the load queue until the data is available at which point the load will be retried. Stores will let the Reorder Buffer know that it's ready to be retired but will not update the cache.
Retire | Once the instruction reaches the head of the Reorder Buffer and the instruction has been completed it will be retired which means it will be removed from the Reorder Buffer and the result value (if any) written into the Register File. For stores, the Reorder Buffer will signal the store queue to retire the store. The store queue will, as soon as the next cycle, tell the LSU to write the store data to the cache. If the store misses in the cache it will wait in the store queue until the cache-line is available. At this point the stores will also CAM the load queue and mark any load to the same address bytes as "mis-speculated".

At a finer level, the processor's pipeline is organized as described below for the various execution paths.

## Front-End Pipeline

![Procyon Front-End Pipeline Diagram](https://raw.githubusercontent.com/0ctobyte/procyon/master/Procyon-Core-FE-Pipeline.jpeg)

This part of the pipeline is the same for all ALU, branch and load/store instructions. It's composed of the Fetch, Decode and Dispatch stages.

### Fetch Stage

The fetch stage is very simple at the moment. It simply takes the current PC (`PC` cycle) and sends it to the iCache to read out (`IT` - iCache tag/data cacheline read, `IR` - pull out 4 byte instruction from cacheline). If there is a cache miss, the fetch unit will signal the Instruction Fetch Queue to retreive the cacheline and stall. Once the cacheline is filled, the fetch unit will resume at the missed PC. If a valid instruction is found in the iCache, the fetch unit will enqueue (`IE` - instruction enqueue) it into the instruction FIFO. It will stall if the instruction FIFO is full. The PC mux will use the redirect address for the PC if a flush is signalled by the back end of the core.

### Decode Stage

In the `DMR` (Decode, Map & Rename) cycle the instruction will be decoded to produce a set of control signals indicating what this instruction does and what source operands it requires and various other bits. In addition, the source registers will be looked up in the Register Alias Table for either the value of the register or the producer of the register value if a previous instruction is in the process of writing to it. This lookup resolves RAW hazards.
The destination register for the instruction (if needed) will be renamed in the Register Alias Table as well thus avoiding WAR and WAW hazards. An entry will be reserved in both the Reorder Buffer and Reservation Station in this cycle and will be filled with the instruction details in the next cycle. If either the Reorder Buffer or the Reservation Station are full, then the pipeline will stall here.

### Dispatch

The Reorder Buffer and the Reservation Station will be updated in this cycle simply enqueuing the new op. Data for source operands will be bypassed from the CDB before enqueuing in the Reservation Station in case the CDB is valid in the same cycle.

## IEU Pipeline

![Procyon IEU Pipeline Diagram](https://raw.githubusercontent.com/0ctobyte/procyon/master/Procyon-Core-IEU-Pipeline.jpeg)

The IEU (Integer Execution Unit) executes all ALU and branch instructions in the execution stage of the pipeline.

### IEU: Integer Execution Unit

#### Execute

The operation is performed in this cycle. Conditional branches are resolved but no redirection of the Front-End will happen in this cycle. The result data and Reorder Buffer entry number (i.e. this number is basically the renaming of the destination register) is prepared to be broad-casted over the Common Data Bus (CDB) in the next cycle (i.e. the "Complete" cycle). Each IEU is connected to it's own CDB so there is no hazard when driving the bus.

#### Complete

The instruction is marked as completed in the Reorder Buffer and it will wait there until it gets to the head of the Reorder Buffer.

#### Retire

Retiring instructions is straightforward for integer ALU instructions; they will simply update the destination register in the Register Alias Table with the calculated value and mark it as "not busy" if it's Reorder Buffer entry number was the last Reorder Buffer entry to update the register value. Branches will redirect the Front-End since it is now known that the branch is no longer speculative.

## LSU Pipeline

![Procyon LSU Pipeline Diagram](https://raw.githubusercontent.com/0ctobyte/procyon/master/Procyon-Core-LSU-Pipeline.jpeg)

The load/store unit performs loads and stores in the execution stage. The main pipeline is split into four cycles but is complicated by data cache misses and structural hazards due to cache fills, older loads/stores replaying or stores retiring.

### LSU: Load/Store Unit

The Load/Store Unit is split into four main cycles assuming a cache hit; `AM`, `DT`, `DW`, and `EX`. There are several structures in the LSU and around it that are key to successful operation. These are the Load Queue, Store Queue and Miss Handling Queue.

#### Address Generation & Mux

For new loads or stores the effective address is calculated. An entry is allocated in either the Load Queue or Store Queue (depending on the instruction) and the address, instruction type and destination Reorder Buffer entry number is stored but if the Load or Store Queue is full, the LSU pipeline will stall here. There is an extra wrinkle in this pipeline cycle; previous loads may be replayed, stores may be retired and cache-lines will be filled and these operations all are muxed into the LSU pipeline. Cache fills have priority followed by retiring stores and then replaying loads and then finally new instructions.

#### Data Cache Data/Tag Read

The Data Cache is queried for tag and the data (it will return the full cache-line) in this cycle. Write data from the next cycle is bypassed here to avoid RAW memory hazards.

#### LQ/SQ Allocate

In the same cycle as `DT` (Data Cache Data/Tag Read), an entry will be allocated in either the Load Queue or Store Queue depending on whether the instruction is a Load or Store with the relevant details stored in the entry.

#### Data Cache Hit Check & Write

Cache-line tags and validity are checked here and if a cache hit is indicated then the load data will be marked valid and retiring store data will be written into the cache.

#### Execute

The execute stage is straightforward. The actual bytes needed by the load instruction is extracted from the cache-line and prepared to be driven on the CDB alongside the Reorder Buffer entry number. If a victim data is provided by the Data Cache it will be sent to the Victim Buffer in this cycle.

#### Complete

The data on the CDB will be used to forward any load data to dependent instructions in any of the Reservation Stations. The Reorder Buffer entry for the instruction will be marked as completed and it'll wait there until it is ready to be retired. Stores will not write to the Data Cache until they are retired to prevent mis-speculated updates to the cache and maintain precise interrupts. Both loads and stores will be kept in the respective queues until they are retired. For loads this allows retiring stores to look up younger loads and mark them as mis-speculated if the address ranges overlap. There is no store data bypassing in the LSU so this is necessary.

#### LQ/SQ Update

During the same cycle as `CM` (complete), the Load Queue and Store Queue will be updated with the Miss Handling Queue tag or told to "sleep" until the next Miss Handling Queue fill request comes through in the case the load or store missed in the cache and the Miss Handling Queue is full. Load & stores will be immediately be marked `replayable` if the cacheline they need is ready in the Miss Handling Queue and the Miss Handling Queue is ready to launch a cache fill request to the LSU.

#### Retire

Loads will be deallocated from the Load Queue if a mis-speculation did not occur. If the load was speculatively executed and an older Store wrote to the same bytes as the load, it'll be marked as mis-speculated in the Reorder Buffer and the Reorder Buffer will flush the entire pipeline and restart execution at the mis-speculated load. Stores will be removed from the Reorder Buffer but not from the Store Queue. Instead they will be marked as non-speculative or retired in the Store Queue. This mechanism is described further below.

#### Store Retire

Retiring stores will be marked as such in the Store Queue. When the Store Queue detects any stores that are ready to be actually written into the Data Cache, it will select one store and send it to the beginning of the LSU pipeline where it'll contend for access to the pipeline with Cache Fills. Once it is in the pipeline it'll go through the same cycles as described above except the data will be written in the Data Cache in the `DW` cycle. In the case that the store misses in the cache, it'll attempt to allocate into the Miss Handling Queue (MHQ). If the Miss Handling Queue is full, the `EX` cycle will signal the Store Queue to put the store to "sleep" and wait for the Miss Handling Queue to indicate that an entry is free at which point it will be "replayed". If the Miss Handling Queue is not full, the store will write it's data into the Miss Handling Queue registers and the Store Queue entry will be deallocated at the end of the `EX` cycle.

#### Load Replay

Loads that miss in the Data Cache will have to be "replayed" later. Loads will attempt to allocate in the Miss Handling Queue on a cache miss. If the Miss Handling Queue is full, the `EX` cycle will signal the Load Queue to put the instruction to "sleep" and wait for the Miss Handling Queue to indicate that an entry is free. If the Miss Handling Queue is not full, the Load Queue will be updated to indicate that it is waiting for the cache-line and which Miss Handling Queue entry will provide the cache-line. When the Miss Handling Queue indicates that it is no longer full, the loads waiting for a Miss Handling Queue entry will be sent to the beginning of the LSU pipeline and compete for access with retiring stores and cache fills and basically go through the same flow as described above. When the Miss Handling Queue is finished retrieving the cache-line for a specific entry it will signal the Load Queue with that Miss Handling Queue entry number. The Load Queue will perform a CAM search on the Miss Handling Queue entry number and "wake up" any loads that were waiting on that data. One of those loads will be selected by the Load Queue and sent to the beginning of the LSU pipeline to be replayed.

### MHQ: Miss Handling Queue

The Miss Handling Queue takes care of any cache misses. It interfaces with the BIU and provides storage for a cache-line of data for each entry.

#### MHQ Lookup

The Miss Handling Queue is looked up in the same cycle as the LSU `EX` cycle. This is to find a matching entry or a new entry for the given load/store address if any exists so that, for loads, the Load Queue can be updated in the next cycle in case of a cache miss and for stores, the store data can be written to the Miss Handling Queue entry in case of a cache miss.

#### MHQ Update

A new entry is allocated in this cycle in case of a cache miss. If an entry already exists for the given load/store address the load/store will be simply be merged with this entry. For stores, this means the store data will be written into the cache-line buffer for the entry (in both the new or existing entry cases). The Miss Handling Queue will interface with the BIU to request data and write received data into the entry merging the received data with the store data. There is a bypass network to select store data to be written into the buffer over received data from the BIU in case they occur on the same cycle.

#### Cache Fills

When a full cache-line is received from the BIU, the Miss Handling Queue will signal the LSU pipeline to perform the Cache Fill. This goes through the same LSU pipeline flow as described above. Cache Fills take priority over any other LSU pipeline operation.
