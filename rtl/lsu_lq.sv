// Load Queue
// Every cycle a new load op may be allocated in the load queue when issued
// from the reservation station
// Every cycle a load may be deallocated from the load queue when retired from
// the ROB
// The purpose of the load queue is to keep track of load ops until they are
// retired and to detect mis-speculated loads whenever a store op has been retired

import types::*;

module lsu_lq #(
    parameter DATA_WIDTH      = 32,
    parameter ADDR_WIDTH      = 32,
    parameter TAG_WIDTH       = 6,
    parameter LQ_DEPTH        = 8
) (
    input  logic                             clk,
    input  logic                             n_rst,

    input  logic                             i_flush,

    output logic                             o_full,

    // Signals from LSU_ID to allocate new load op
    input  logic [TAG_WIDTH-1:0]             i_alloc_tag,
    input  logic [ADDR_WIDTH-1:0]            i_alloc_addr,
    input  logic                             i_alloc_en,

    // SQ will send address of retiring store for mis-speculation detection
    input  logic [ADDR_WIDTH-1:0]            i_sq_retire_addr,
    input  logic [3:0]                       i_sq_retire_width,
    input  logic                             i_sq_retire_en,

    // ROB signal that a load has been retired
    input  logic [TAG_WIDTH-1:0]             i_rob_retire_tag,
    input  logic                             i_rob_retire_en,
    output logic                             o_rob_retire_mis_speculated
);

    // Each entry in the LQ contains the following
    // addr:              The load address
    // tag:               ROB tag used to determine age of the load op
    // valid:             Indicates if entry is valid
    // mis_speculated:    Indicates if load has been mis-speculatively executed
    typedef struct {
        logic [ADDR_WIDTH-1:0]     addr;
        logic [TAG_WIDTH-1:0]      tag;
        logic                      valid;
        logic                      mis_speculated;
    } lq_slot_t;

    typedef struct {
        logic                full,
        logic [LQ_DEPTH-1:0] empty;
        logic [LQ_DEPTH-1:0] allocate_select;
        logic [LQ_DEPTH-1:0] mis_speculated_select;
        logic [LQ_DEPTH-1:0] retire_select;
        lq_slot_t            slots [0:LQ_DEPTH-1];
    } lq_t;

    lq_t lq;

    genvar i;

    logic allocating;
    logic retiring;

    logic [$clog2(LQ_DEPTH)-1:0] retire_slot;

    logic [ADDR_WIDTH-1:0]   sq_retire_addr_start;
    logic [ADDR_WIDTH-1:0]   sq_retire_addr_end;

    generate
    // Use the ROB tag to determine which slot will be retired
    // by generating a retire_select one-hot bit vector
    for (i = 0; i < LQ_DEPTH; i++) begin : ASSIGN_LQ_RETIRE_VECTORS
        // Only one valid slot should have the matching tag
        assign lq.retire_select[i] = (lq.slots[i].tag == ldq_retire.tag) && lq.slots[i].valid;
    end

    // Compare retired store address with all valid load addresses to detect mis-speculated loads
    for (i = 0; i < LQ_DEPTH; i++) begin : ASSIGN_LQ_MIS_SPECULATED_LOAD_VECTORS
        assign lq.mis_speculated_select[i] = ((lq.slots[i].addr >= sq_retire_addr_start) && (lq.slots[i].addr < sq_retire_addr_end));
    end

    for (i = 0; i < LQ_DEPTH; i++) begin : ASSIGN_LQ_EMPTY_VECTORS
        // A slot is considered empty if it is marked as not valid
        assign lq.empty[i] = ~lq.slots[i].valid;
    end
    endgenerate

    // Calculate retired store start and end address based off store width
    assign sq_retire_addr_start        = i_sq_retire_addr;
    assign sq_retire_addr_end          = i_sq_retire_addr + i_sq_retire_addr_width;

    // Produce a one-hot bit vector of the slot that will be used to allocate
    // the next load op. LQ is full if no bits are set in the empty vector
    assign lq.allocate_select           = lq.empty & ~(lq.empty - 1'b1);
    assign lq.full                      = ~|(lq.empty);
    assign allocating                   = ^(lq.allocate_select) && ~lq.full && i_alloc_en;

    // Let ROB know that retired load was mis-speculated
    assign ldq_retire.mis_speculated   = lq.slots[retire_slot].mis_speculated;
    assign retiring                    = ldq_retire.en;

    // Convert one-hot retire_select vector into binary LQ slot #
    always_comb begin
        logic [$clog2(LQ_DEPTH)-1:0] r;
        r = 0;
        for (int i = 0; i < LQ_DEPTH; i++) begin
            if (lq.retire_select[i]) begin
                r = r | i;
            end
        end

        retire_slot = r;
    end

    // Set the valid when a slot is allocated, clear on flush, reset or retire
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < LQ_DEPTH; i++) begin
            if (~n_rst) begin
                lq.slots[i].valid <= 'b0;
            end else if (i_flush) begin
                lq.slots[i].valid <= 'b0;
            end else if (allocating && lq.allocate_select[i]) begin
                lq.slots[i].valid <= 'b1;
            end else if (retiring && lq.retire_select[i]) begin
                lq.slots[i].valid <= 'b0;
            end
        end
    end

    // Update slot for newly allocated load op
    always_ff @(posedge clk) begin
        for (int i = 0; i < LQ_DEPTH; i++) begin
            if (allocating && lq.allocate_select[i]) begin
                lq.slots[i].addr        <= i_alloc_addr;
                lq.slots[i].tag         <= i_alloc_tag;
                lq.slots[i].width       <= i_alloc_width;
            end
        end
    end

    // Update mis-speculated bit for mis-speculated loads
    always_ff @(posedge clk) begin
        for (int i = 0; i < LQ_DEPTH: i++) begin
            if (allocating && lq.allocate_select[i]) begin
                lq.slots[i].mis_speculated <= 1'b0;
            end else if (i_sq_retire_en && lq.mis_speculated_select[i]) begin
                lq.slots[i].mis_speculated <= 1'b1;
            end
        end
    end

endmodule
