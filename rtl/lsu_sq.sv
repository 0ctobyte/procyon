// Store Queue
// Every cycle a new store op may be allocated in the store queue when issued
// from the reservation station
// Every cycle a store may be deallocated from the store queue when retired
// from the ROB
// The purpose of the store queue is to keep track of store ops and commit
// them to memory in program order and to detect mis-speculated loads in
// the load queue

import types::*;

module lsu_sq #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter TAG_WIDTH     = 6,
    parameter SQ_DEPTH      = 8,
    parameter SQ_TAG_WIDTH  = 3,
) (
    input  logic                             clk,
    input  logic                             n_rst,

    input  logic                             i_flush,

    output logic                             o_full,

    // Signals from LSU_ID to allocate new store op in SQ
    input  logic [DATA_WIDTH-1:0]            i_alloc_data,
    input  logic [TAG_WIDTH-1:0]             i_alloc_tag,
    input  logic [ADDR_WIDTH-1:0]            i_alloc_addr,
    input  logic [3:0]                       i_alloc_width,
    input  logic                             i_alloc_en,

    // Retired stores need to look up in D$ and write data to D$ or allocate
    // in MSHQ if store misses in D$. Stall ROB if MSHQ is full and store misses
    input  logic                             i_sq_retire_hit,
    input  logic                             i_sq_retire_mshq_full,
    output logic [DATA_WIDTH-1:0]            o_sq_retire_data,
    output logic [ADDR_WIDTH-1:0]            o_sq_retire_addr,
    output logic [3:0]                       o_sq_retire_width,
    output logic                             o_sq_retire_hit,
    output logic                             o_sq_retire_en,

    // ROB signal that a store has been retired
    sq_retire_if.sink                        sq_retire
);

    // Each SQ slot contains:
    // addr:        Store address updated in ID stage
    // data:        Store data updated in ID stage
    // width:       Indicates which bytes of the data should be written
    // tag:         Destination tag in ROB (used for age comparison for store-to-load forwarding)
    // valid:       Indicates if slot is valid i.e. not empty
    typedef struct {
        logic [ADDR_WIDTH-1:0]   addr;
        logic [DATA_WIDTH-1:0]   data;
        logic [3:0]              width;
        logic [TAG_WIDTH-1:0]    tag;
        logic                    valid;
    } sq_slot_t;

    typedef struct {
        logic                full;
        logic [SQ_DEPTH-1:0] empty;
        logic [SQ_DEPTH-1:0] allocate_select;
        logic [SQ_DEPTH-1:0] retire_select;
        sq_slot_t            slots [0:SQ_DEPTH-1];
    } sq_t;

    sq_t sq;

    genvar i;

    logic allocating;
    logic retiring;

    logic [SQ_TAG_WIDTH-1:0] retire_slot;

    generate
    // Use the ROB tag to determine which slot will be retired
    // by generating a retire_select one-hot bit vector
    for (i = 0; i < SQ_DEPTH; i++) begin : ASSIGN_SQ_RETIRE_VECTORS
        // Only one valid slot should have the matching tag
        assign sq.retire_select[i] = (sq.slots[i].tag == sq_retire.tag) && sq.slots[i].valid;
    end

    for (i = 0; i < SQ_DEPTH; i++) begin : ASSIGN_SQ_EMPTY_VECTORS
        // A slot is considered empty if it is marked as not valid
        assign sq.empty[i] = ~sq.slots[i].valid;
    end
    endgenerate

    // This will produce a one-hot vector of the slot that will be used
    // to allocate the next store op. SQ is full if no bits are set in the
    // empty vector
    assign sq.allocate_select         = sq.empty & ~(sq.empty - 1'b1);
    assign sq.full                    = ~|(sq.empty);
    assign allocating                 = ^(sq.allocate_select) && ~sq.full && i_alloc_en;

    // Assign outputs to write retired store data to D$ if hit
    // If store misses then allocate/merge retired store in MSHQ
    // Enable bit is to mux D$ input between MSHQ data write and retired store
    // as well as to mux MSHQ input between LSU_HIT miss write and retired store miss
    // The retiring store address and width and retire_en signals is also
    // sent to the LQ for possible load bypass violation detection
    assign o_sq_retire_data           = sq.slots[retire_slot].data;
    assign o_sq_retire_addr           = sq.slots[retire_slot].addr;
    assign o_sq_retire_width          = sq.slots[retire_slot].width;
    assign o_sq_retire_hit            = i_sq_retire_hit;
    assign o_sq_retire_en             = sq_retire.en;

    // Stall ROB from retiring store if store misses in cache and MSHQ is full
    assign sq_retire.stall            = i_sq_retire_mshq_full && ~i_sq_retire_hit;
    assign retiring                   = sq_retire.en && ~sq_retire.stall;

    // Assign output
    assign o_full                     = sq.full;

    // Convert one-hot retire_select vector into binary SQ slot #
    always_comb begin
        logic [SQ_TAG_WIDTH-1:0] r;
        r = 0;
        for (int i = 0; i < SQ_DEPTH; i++) begin
            if (sq.retire_select[i]) begin
                r = r | i;
            end
        end

        retire_slot = r;
    end

    // Set the valid bit for a slot only if new store op is being allocated
    // Clear valid bit on flush, reset and store retire
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < SQ_DEPTH; i++) begin
            if (~n_rst) begin
                sq.slots[i].valid <= 'b0;
            end else if (i_flush) begin
                sq.slots[i].valid <= 'b0;
            end else if (allocating && sq.allocate_select[i]) begin
                sq.slots[i].valid <= 'b1;
            end else if (retiring && sq.retire_select[i]) begin
                sq.slots[i].valid <= 'b0;
            end
        end
    end

    // Update slot for newly allocated store op
    always_ff @(posedge clk) begin
        for (int i = 0; i < SQ_DEPTH; i++) begin
            if (allocating && sq.allocate_select[i]) begin
                sq.slots[i].data       <= i_alloc_data;
                sq.slots[i].addr       <= i_alloc_addr;
                sq.slots[i].width      <= i_alloc_width;
                sq.slots[i].tag        <= i_alloc_tag;
            end
        end
    end

endmodule
