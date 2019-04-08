// Store Queue
// Every cycle a new store op may be allocated in the store queue when issued from the reservation station
// Every cycle a store may be launched to memory from the store queue after being retired from the ROB
// The purpose of the store queue is to keep track of store ops and commit them to memory in program order
// and to detect mis-speculated loads in the load queue

`include "common.svh"
import procyon_types::*;

module lsu_sq (
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_flush,
    output logic                            o_full,

    // Signals from LSU_ID to allocate new store op in SQ
    input  logic                            i_alloc_en,
    input  procyon_lsu_func_t               i_alloc_lsu_func,
    input  procyon_tag_t                    i_alloc_tag,
    input  procyon_addr_t                   i_alloc_addr,
    input  procyon_data_t                   i_alloc_data,

    // Send out store to LSU on retirement and to the load queue for
    // detection of mis-speculated loads
    input  logic                            i_sq_retire_stall,
    output logic                            o_sq_retire_en,
    output procyon_sq_select_t              o_sq_retire_select,
    output procyon_lsu_func_t               o_sq_retire_lsu_func,
    output procyon_addr_t                   o_sq_retire_addr,
    output procyon_tag_t                    o_sq_retire_tag,
    output procyon_data_t                   o_sq_retire_data,

    // Signal from the LSU to indicate if the last retiring store needs to be retried
    input  logic                            i_update_en,
    input  procyon_sq_select_t              i_update_select,
    input  logic                            i_update_retry,
    input  logic                            i_update_mhq_full,

    // ROB signal that a store has been retired
    input  logic                            i_rob_retire_en,
    input  procyon_tag_t                    i_rob_retire_tag,
    output logic                            o_rob_retire_ack
);

    typedef logic [`SQ_DEPTH-1:0]           sq_vec_t;
    typedef logic [$clog2(`SQ_DEPTH)-1:0]   sq_idx_t;

    // Each SQ slot contains:
    // lsu_func:        Indicates type of store op (SB, SH, SW)
    // addr:            Store address updated in ID stage
    // data:            Store data updated in ID stage
    // tag:             Destination tag in ROB (used for age comparison for store-to-load forwarding)
    // valid:           Indicates if slot is valid i.e. not empty
    // nonspeculative:  Indicates if slot is no longer speculative and can be retired/written out to cache
    // launched:        Indicates if the retired store has been launched to LSU_EX
    typedef struct packed {
        procyon_lsu_func_t                  lsu_func;
        procyon_addr_t                      addr;
        procyon_data_t                      data;
        procyon_tag_t                       tag;
        logic                               valid;
        logic                               nonspeculative;
        logic                               launched;
    } sq_slot_t;

/* verilator lint_off MULTIDRIVEN */
    sq_slot_t [`SQ_DEPTH-1:0]               sq_slots;
/* verilator lint_on  MULTIDRIVEN */
    logic                                   sq_full;
    sq_vec_t                                sq_empty;
    sq_vec_t                                sq_retirable;
    sq_vec_t                                sq_allocate_select;
    sq_vec_t                                sq_rob_select;
    procyon_sq_select_t                     sq_update_select;
    logic                                   sq_update_retry;
    procyon_sq_select_t                     sq_retire_select;
    sq_idx_t                                retire_slot;
    logic                                   retire_en;

    // This will produce a one-hot vector of the slot that will be used
    // to allocate the next store op. SQ is full if no bits are set in the
    // empty vector
    assign sq_allocate_select               = {(`SQ_DEPTH){i_alloc_en}} & (sq_empty & ~(sq_empty - 1'b1));
    assign sq_full                          = sq_empty == {(`SQ_DEPTH){1'b0}};

    // Retire stores that are non-speculative
    assign retire_en                        = sq_retirable != {(`SQ_DEPTH){1'b0}};
    assign sq_retire_select                 = {(`SQ_DEPTH){~i_sq_retire_stall}} & (sq_retirable & ~(sq_retirable - 1'b1));

    assign sq_update_select                 = {(`SQ_DEPTH){i_update_en}} & i_update_select;
    assign sq_update_retry                  = i_update_retry && i_update_mhq_full;

    // Output full signal
    // FIXME: Can this be registered?
    assign o_full                           = sq_full;

    always_comb begin
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            // A slot is ready to be retired if it is non-speculative and valid and not already launched
            sq_retirable[i]  = sq_slots[i].nonspeculative & ~sq_slots[i].launched & sq_slots[i].valid;

            // Use the ROB tag to determine which slot is no longer speculative and can be retired (i.e. written out to the cache)
            // Only one valid slot should have the matching tag
            sq_rob_select[i] = i_rob_retire_en & (sq_slots[i].tag == i_rob_retire_tag) & sq_slots[i].valid;

            // A slot is considered empty if it is marked as not valid
            sq_empty[i]      = ~sq_slots[i].valid;
        end
    end

    // Convert one-hot retire_select vector into binary SQ slot #
    always_comb begin
        retire_slot = {($clog2(`SQ_DEPTH)){1'b0}};

        for (int i = 0; i < `SQ_DEPTH; i++) begin
            if (sq_retire_select[i]) begin
                retire_slot = sq_idx_t'(i);
            end
        end
    end

    // Send ack back to ROB when launching the retired store
    always_ff @(posedge clk) begin
        if (~n_rst) o_rob_retire_ack <= 1'b0;
        else        o_rob_retire_ack <= i_rob_retire_en & retire_en & (sq_slots[retire_slot].tag == i_rob_retire_tag);
    end

    // Retire stores to D$ or to the MHQ if it misses in the cache
    // The retiring store address and type and retire_en signals is also
    // sent to the LQ for possible load bypass violation detection
    always_ff @(posedge clk) begin
        o_sq_retire_data     <= sq_slots[retire_slot].data;
        o_sq_retire_addr     <= sq_slots[retire_slot].addr;
        o_sq_retire_tag      <= sq_slots[retire_slot].tag;
        o_sq_retire_lsu_func <= sq_slots[retire_slot].lsu_func;
        o_sq_retire_select   <= sq_retire_select;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_sq_retire_en <= 1'b0;
        else        o_sq_retire_en <= ~i_flush & retire_en;
    end

    // Set the valid bit for a slot only if new store op is being allocated
    // Clear valid bit on flush, reset and a successful retired store
    // On a flush, don't clear the valid bit if the entry is marked nonspeculative and is still valid!
    // Those stores still need to be written out to the cache
    always_ff @(posedge clk) begin
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            if (~n_rst) sq_slots[i].valid <= 1'b0;
            else        sq_slots[i].valid <= i_flush ? sq_slots[i].nonspeculative & sq_slots[i].valid : sq_allocate_select[i] | (sq_update_select[i] ? sq_update_retry : sq_slots[i].valid);
        end
    end

    // Set the launched bit when the store is retired
    // Clear it if the store retire fails or when allocating a new entry
    always_ff @(posedge clk) begin
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            sq_slots[i].launched <= ~sq_allocate_select[i] & (sq_retire_select[i] | (sq_update_select[i] ? ~sq_update_retry : sq_slots[i].launched));
        end
    end

    // Set the non-speculative bit when the ROB indicates that the store is ready to be retired
    always_ff @(posedge clk) begin
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            sq_slots[i].nonspeculative <= ~sq_allocate_select[i] & sq_rob_select[i];
        end
    end

    // Update slot for newly allocated store op
    always_ff @(posedge clk) begin
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            if (sq_allocate_select[i]) begin
                sq_slots[i].data       <= i_alloc_data;
                sq_slots[i].addr       <= i_alloc_addr;
                sq_slots[i].lsu_func   <= i_alloc_lsu_func;
                sq_slots[i].tag        <= i_alloc_tag;
            end
        end
    end

endmodule
