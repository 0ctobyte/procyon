// Store Queue
// Every cycle a new store op may be allocated in the store queue when issued
// from the reservation station
// Every cycle a store may be deallocated from the store queue when retired
// from the ROB
// The purpose of the store queue is to keep track of store ops and commit
// them to memory in program order and to detect mis-speculated loads in
// the load queue

`include "common.svh"
import procyon_types::*;

/* verilator lint_off MULTIDRIVEN */
module lsu_sq #(
    parameter SQ_DEPTH = `SQ_DEPTH
) (
    input  logic                clk,
    input  logic                n_rst,

    input  logic                i_flush,
    output logic                o_full,

    // Signals from LSU_ID to allocate new store op in SQ
    input  procyon_data_t       i_alloc_data,
    input  procyon_tag_t        i_alloc_tag,
    input  procyon_addr_t       i_alloc_addr,
    input  procyon_lsu_func_t   i_alloc_lsu_func,
    input  logic                i_alloc_en,

    // Send out store to D$ on retirement and to the load queue for
    // detection of mis-speculated loads
    input  logic                i_sq_retire_dc_hit,
    input  logic                i_sq_retire_msq_full,
    output procyon_data_t       o_sq_retire_data,
    output procyon_addr_t       o_sq_retire_addr,
    output procyon_lsu_func_t   o_sq_retire_lsu_func,
    output logic                o_sq_retire_en,

    // ROB signal that a store has been retired
    input  procyon_tag_t        i_rob_retire_tag,
    input  logic                i_rob_retire_en,
    output logic                o_rob_retire_stall
);

    // Each SQ slot contains:
    // lsu_func:    Indicates type of store op (SB, SH, SW)
    // addr:        Store address updated in ID stage
    // data:        Store data updated in ID stage
    // tag:         Destination tag in ROB (used for age comparison for store-to-load forwarding)
    // valid:       Indicates if slot is valid i.e. not empty
    typedef struct packed {
        procyon_lsu_func_t       lsu_func;
        procyon_addr_t           addr;
        procyon_data_t           data;
        procyon_tag_t            tag;
        logic                    valid;
    } sq_slot_t;

    typedef struct packed {
        logic                    full;
        logic     [SQ_DEPTH-1:0] empty;
        logic     [SQ_DEPTH-1:0] allocate_select;
        logic     [SQ_DEPTH-1:0] retire_select;
    } sq_t;

    sq_slot_t [SQ_DEPTH-1:0]         sq_slots;
/* verilator lint_off UNOPTFLAT */
    sq_t                             sq;
/* verilator lint_on  UNOPTFLAT */
    logic                            allocating;
    logic                            retiring;
    logic                            retire_stall;
    logic     [$clog2(SQ_DEPTH)-1:0] retire_slot;

    genvar gvar;
    generate
        // Use the ROB tag to determine which slot will be retired
        // by generating a retire_select one-hot bit vector
        for (gvar = 0; gvar < SQ_DEPTH; gvar++) begin : ASSIGN_SQ_RETIRE_VECTORS
            // Only one valid slot should have the matching tag
            assign sq.retire_select[gvar] = (sq_slots[gvar].tag == i_rob_retire_tag) && sq_slots[gvar].valid;
        end

        for (gvar = 0; gvar < SQ_DEPTH; gvar++) begin : ASSIGN_SQ_EMPTY_VECTORS
            // A slot is considered empty if it is marked as not valid
            assign sq.empty[gvar] = ~sq_slots[gvar].valid;
        end
    endgenerate

    // This will produce a one-hot vector of the slot that will be used
    // to allocate the next store op. SQ is full if no bits are set in the
    // empty vector
    assign sq.allocate_select         = sq.empty & ~(sq.empty - 1'b1);
    assign sq.full                    = ~|(sq.empty);
    assign allocating                 = ^(sq.allocate_select) && ~sq.full && i_alloc_en;

    // Assign outputs to write retired store data to D$ if hit
    // If store misses then allocate/merge retired store in MSQ
    // The retiring store address and type and retire_en signals is also
    // sent to the LQ for possible load bypass violation detection
    assign o_sq_retire_data           = sq_slots[retire_slot].data;
    assign o_sq_retire_addr           = sq_slots[retire_slot].addr;
    assign o_sq_retire_lsu_func       = sq_slots[retire_slot].lsu_func;
    assign o_sq_retire_en             = i_rob_retire_en;

    // Stall ROB from retiring store if store misses in cache and MSQ is full
    assign retire_stall               = i_sq_retire_msq_full && ~i_sq_retire_dc_hit;
    assign o_rob_retire_stall         = retire_stall;
    assign retiring                   = i_rob_retire_en && ~retire_stall;

    // Output full signal
    assign o_full                     = sq.full;

    // Convert one-hot retire_select vector into binary SQ slot #
    always_comb begin
        int r;
        r = 0;
        for (int i = 0; i < SQ_DEPTH; i++) begin
            if (sq.retire_select[i]) begin
                r = r | i;
            end
        end
        retire_slot = r[$clog2(SQ_DEPTH)-1:0];
    end

    // Set the valid bit for a slot only if new store op is being allocated
    // Clear valid bit on flush, reset and store retire
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < SQ_DEPTH; i++) begin
            if (~n_rst) begin
                sq_slots[i].valid <= 'b0;
            end else if (i_flush) begin
                sq_slots[i].valid <= 'b0;
            end else if (allocating && sq.allocate_select[i]) begin
                sq_slots[i].valid <= 'b1;
            end else if (retiring && sq.retire_select[i]) begin
                sq_slots[i].valid <= 'b0;
            end
        end
    end

    // Update slot for newly allocated store op
    always_ff @(posedge clk) begin
        for (int i = 0; i < SQ_DEPTH; i++) begin
            if (allocating && sq.allocate_select[i]) begin
                sq_slots[i].data       <= i_alloc_data;
                sq_slots[i].addr       <= i_alloc_addr;
                sq_slots[i].lsu_func   <= i_alloc_lsu_func;
                sq_slots[i].tag        <= i_alloc_tag;
            end
        end
    end

endmodule
/* verilator lint_on  MULTIDRIVEN */
