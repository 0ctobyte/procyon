// Load Queue
// Every cycle a new load op may be allocated in the load queue when issued
// from the reservation station
// Every cycle a load may be deallocated from the load queue when retired from
// the ROB
// The purpose of the load queue is to keep track of load ops until they are
// retired and to detect mis-speculated loads whenever a store op has been retired

`include "common.svh"
import procyon_types::*;

/* verilator lint_off MULTIDRIVEN */
module lsu_lq #(
    parameter LQ_DEPTH = `LQ_DEPTH
) (
    input  logic                 clk,
    input  logic                 n_rst,

    input  logic                 i_flush,
    output logic                 o_full,

    // Signals from LSU_ID to allocate new load op
    input  procyon_tag_t         i_alloc_tag,
    input  procyon_addr_t        i_alloc_addr,
    input  logic                 i_alloc_en,

    // SQ will send address of retiring store for mis-speculation detection
    input  procyon_addr_t        i_sq_retire_addr,
    input  procyon_lsu_func_t    i_sq_retire_lsu_func,
    input  logic                 i_sq_retire_en,

    // ROB signal that a load has been retired
    input  procyon_tag_t         i_rob_retire_tag,
    input  logic                 i_rob_retire_en,
    output logic                 o_rob_retire_mis_speculated
);

    // Each entry in the LQ contains the following
    // addr:              The load address
    // tag:               ROB tag used to determine age of the load op
    // valid:             Indicates if entry is valid
    // mis_speculated:    Indicates if load has been mis-speculatively executed
    typedef struct packed {
        procyon_addr_t           addr;
        procyon_tag_t            tag;
        logic                    valid;
        logic                    mis_speculated;
    } lq_slot_t;

    typedef struct packed {
        logic                    full;
        logic     [LQ_DEPTH-1:0] empty;
        logic     [LQ_DEPTH-1:0] allocate_select;
        logic     [LQ_DEPTH-1:0] mis_speculated_select;
        logic     [LQ_DEPTH-1:0] retire_select;
    } lq_t;

    lq_slot_t [LQ_DEPTH-1:0]         lq_slots;
/* verilator lint_off UNOPTFLAT */
    lq_t                             lq;
/* verilator lint_on  UNOPTFLAT */
    logic                            allocating;
    logic                            retiring;
    logic     [$clog2(LQ_DEPTH)-1:0] retire_slot;
    procyon_addr_t                   sq_retire_addr_start;
    procyon_addr_t                   sq_retire_addr_end;

    genvar gvar;
    generate
        // Use the ROB tag to determine which slot will be retired
        // by generating a retire_select one-hot bit vector
        for (gvar = 0; gvar < LQ_DEPTH; gvar++) begin : ASSIGN_LQ_RETIRE_VECTORS
            // Only one valid slot should have the matching tag
            assign lq.retire_select[gvar] = (lq_slots[gvar].tag == i_rob_retire_tag) && lq_slots[gvar].valid;
        end

        // Compare retired store address with all valid load addresses to detect mis-speculated loads
        for (gvar = 0; gvar < LQ_DEPTH; gvar++) begin : ASSIGN_LQ_MIS_SPECULATED_LOAD_VECTORS
            assign lq.mis_speculated_select[gvar] = ((lq_slots[gvar].addr >= sq_retire_addr_start) && (lq_slots[gvar].addr < sq_retire_addr_end));
        end

        for (gvar = 0; gvar < LQ_DEPTH; gvar++) begin : ASSIGN_LQ_EMPTY_VECTORS
            // A slot is considered empty if it is marked as not valid
            assign lq.empty[gvar] = ~lq_slots[gvar].valid;
        end
    endgenerate

    // Grab retired store address
    assign sq_retire_addr_start         = i_sq_retire_addr;

    // Produce a one-hot bit vector of the slot that will be used to allocate
    // the next load op. LQ is full if no bits are set in the empty vector
    assign lq.allocate_select           = lq.empty & ~(lq.empty - 1'b1);
    assign lq.full                      = ~|(lq.empty);
    assign allocating                   = ^(lq.allocate_select) && ~lq.full && i_alloc_en;

    // Let ROB know that retired load was mis-speculated
    assign o_rob_retire_mis_speculated  = lq_slots[retire_slot].mis_speculated;
    assign retiring                     = i_rob_retire_en;

    // Ouput full signal
    assign o_full                       = lq.full;

    // Calculate retiring store end address based off of store type
    always_comb begin
        case (i_sq_retire_lsu_func)
            LSU_FUNC_SB: sq_retire_addr_end = i_sq_retire_addr + 32'b0001;
            LSU_FUNC_SH: sq_retire_addr_end = i_sq_retire_addr + 32'b0010;
            LSU_FUNC_SW: sq_retire_addr_end = i_sq_retire_addr + 32'b0100;
            default:     sq_retire_addr_end = i_sq_retire_addr + 32'b0100;
        endcase
    end

    // Convert one-hot retire_select vector into binary LQ slot #
    always_comb begin
        int r;
        r = 0;
        for (int i = 0; i < LQ_DEPTH; i++) begin
            if (lq.retire_select[i]) begin
                r = r | i;
            end
        end
        retire_slot = r[$clog2(LQ_DEPTH)-1:0];
    end

    // Set the valid when a slot is allocated, clear on flush, reset or retire
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < LQ_DEPTH; i++) begin
            if (~n_rst) begin
                lq_slots[i].valid <= 'b0;
            end else if (i_flush) begin
                lq_slots[i].valid <= 'b0;
            end else if (allocating && lq.allocate_select[i]) begin
                lq_slots[i].valid <= 'b1;
            end else if (retiring && lq.retire_select[i]) begin
                lq_slots[i].valid <= 'b0;
            end
        end
    end

    // Update slot for newly allocated load op
    always_ff @(posedge clk) begin
        for (int i = 0; i < LQ_DEPTH; i++) begin
            if (allocating && lq.allocate_select[i]) begin
                lq_slots[i].addr        <= i_alloc_addr;
                lq_slots[i].tag         <= i_alloc_tag;
            end
        end
    end

    // Update mis-speculated bit for mis-speculated loads
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < LQ_DEPTH; i++) begin
            if (~n_rst) begin
                lq_slots[i].mis_speculated <= 1'b0;
            end else if (allocating && lq.allocate_select[i]) begin
                lq_slots[i].mis_speculated <= 1'b0;
            end else if (i_sq_retire_en && lq.mis_speculated_select[i]) begin
                lq_slots[i].mis_speculated <= 1'b1;
            end
        end
    end

endmodule
/* verilator lint_on  MULTIDRIVEN */
