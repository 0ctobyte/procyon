// Store Queue
// Every cycle a new store op may be allocated in the store queue when issued
// from the reservation station
// Every cycle a store may be deallocated from the store queue when retired
// from the ROB
// The purpose of the store queue is to keep track of store ops and commit
// them to memory in program order and to detect mis-speculated loads in 
// the load queue

import types::*;

module lsu_stq #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter TAG_WIDTH  = 6,
    parameter STQ_DEPTH  = 8
) (
    input logic             clk,
    input logic             n_rst,

    input logic             i_flush,

    // LSU_AGU <-> STQ interface to enqueue new store op
    stq_enqueue_if.sink     stq_enqueue,

    // Store data from LSU_MEM
    stq_mem_if.sink         stq_mem,

    // ROB signal that a store has been retired
    stq_retire_if.sink         stq_retire,

    // Send address to LDQ of retired store for conflict detection
    ldq_conflict_if.source  ldq_conflict,

    // Memory interface for retired stores
    dp_ram_wr_if.sys        dp_ram_wr
);

    // Each STQ slot contains:
    // addr:  Store address updated by AGU in AG stage
    // data:  Store data updated in MEM stage
    // tag:   Destination tag in ROB (used for age comparison for store-to-load forwarding)
    // valid: Indicates if slot is valid i.e. not empty
    typedef struct {
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [TAG_WIDTH-1:0]  tag;
        logic                  valid;
    } stq_slot_t;

    typedef struct {
        logic                 full;
        logic [STQ_DEPTH-1:0] empty;
        logic [STQ_DEPTH-1:0] enqueue_select;
        logic [STQ_DEPTH-1:0] st_data_select;
        logic [STQ_DEPTH-1:0] retire_select;
        stq_slot_t            slots [0:STQ_DEPTH-1];
    } stq_t;

    stq_t stq;

    genvar i;

    logic enqueuing;

    logic [$clog2(STQ_DEPTH)-1:0] enqueue_slot;
    logic [$clog2(STQ_DEPTH)-1:0] retire_slot;

    generate
    // Use the ROB tag to determine which slot will be retired
    // by generating a retire_select one-hot bit vector
    for (i = 0; i < STQ_DEPTH; i++) begin : ASSIGN_STQ_RETIRE_VECTORS
        // Only one valid slot should have the matching tag
        assign stq.retire_select[i] = (stq.slots[i].tag == stq_retire.tag) && stq.slots[i].valid;
    end

    for (i = 0; i < STQ_DEPTH; i++) begin : ASSIGN_STQ_EMPTY_VECTORS
        // A slot is considered empty if it is marked as not valid
        assign stq.empty[i] = ~stq.slots[i].valid;
    end
    endgenerate

    // This will produce a one-hot vector of the slot that will be used
    // to enqueue the next store op. STQ is full if no bits are set in the
    // empty vector
    assign stq.enqueue_select  = stq.empty & ~(stq.empty - 1'b1);
    assign stq.full            = ~|(stq.empty);

    // Assign outputs to AGU, use enable bit to determine if enqueuing or not
    assign stq_enqueue.full    = stq.full;
    assign stq_enqueue.stq_tag = enqueue_slot;
    assign enqueuing           = ^(stq.enqueue_select) && stq_enqueue.en;

    // Convert stq_tag from MEM stage to one-hot slot select vector
    assign stq.st_data_select  = 1 << stq_mem.stq_tag;

    // Assign outputs to LDQ for load bypass violation
    assign ldq_conflict.addr = stq.slots[retire_slot].addr;
    assign ldq_conflict.en   = stq_retire.en;

    // Assign outputs to memory system for retired stores
    assign dp_ram_wr.en      = stq_retire.en;
    assign dp_ram_wr.addr    = stq.slots[retire_slot].addr;
    assign dp_ram_wr.data    = stq.slots[retire_slot].data;

    // Convert one-hot enqueue_select vector into binary STQ slot #
    always_comb begin
        logic [$clog2(STQ_DEPTH)-1:0] r;
        r = 0;
        for (int i = 0; i < STQ_DEPTH; i++) begin
            if (stq.enqueue_select[i]) begin
                r = r | i;
            end
        end

        enqueue_slot = r;
    end

    // Convert one-hot retire_select vector into binary STQ slot #
    always_comb begin
        logic [$clog2(STQ_DEPTH)-1:0] r;
        r = 0;
        for (int i = 0; i < STQ_DEPTH; i++) begin
            if (stq.retire_select[i]) begin
                r = r | i;
            end
        end

        retire_slot = r;
    end

    // Set the valid bit for a slot only if new store op is being enqueued
    // Clear valid bit on flush, reset and store retire
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < STQ_DEPTH; i++) begin
            if (~n_rst) begin
                stq.slots[i].valid <= 'b0;
            end else if (i_flush) begin
                stq.slots[i].valid <= 'b0;
            end else if (enqueuing && stq.enqueue_select[i]) begin
                stq.slots[i].valid <= 'b1;
            end else if (stq_retire.en && stq.retire_select[i]) begin
                stq.slots[i].valid <= 'b0;
            end
        end
    end

    // Update slot for newly enqueued store op
    always_ff @(posedge clk) begin
        for (int i = 0; i < STQ_DEPTH; i++) begin
            if (enqueuing && stq.enqueue_select[i]) begin
                stq.slots[i].addr <= stq_enqueue.addr;
                stq.slots[i].tag  <= stq_enqueue.tag;
            end
        end
    end

    // Update store data
    always_ff @(posedge clk) begin
        for (int i = 0; i < STQ_DEPTH; i++) begin
            if (stq_mem.en && stq.st_data_select[i]) begin
                stq.slots[i].data <= stq_mem.data;
            end
        end
    end

endmodule
