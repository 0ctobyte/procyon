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

    // Signals from the LSU and MHQ to indicate if the last retiring store needs to be retried
    input  logic                            i_update_en,
    input  procyon_sq_select_t              i_update_select,
    input  logic                            i_update_retry,
    input  logic                            i_update_mhq_retry,

    // MHQ fill interface for waking up waiting stores
    input  logic                            i_mhq_fill_en,

    // ROB signal that a store has been retired
    input  logic                            i_rob_retire_en,
    input  procyon_tag_t                    i_rob_retire_tag,
    output logic                            o_rob_retire_ack
);

    typedef logic [$clog2(`SQ_DEPTH)-1:0]   sq_idx_t;

    // Each SQ slot is in one of the following states:
    // INVALID:        Slot is empty
    // VALID:          Slot contains a valid but not retired store operation
    // MHQ_FILL_WAIT:  Slot contains a store op that is waiting for an MHQ fill broadcast
    // NONSPECULATIVE: Slot contains a store that is at the head of the ROB and thus is ready to be retired
    // LAUNCHED:       Slot contains a retired store that has been launched into the LSU pipeline
    //                 It must wait in this state until the LSU indicates if it was retired successfully or if it needs to be relaunched
    typedef enum logic [2:0] {
        SQ_STATE_INVALID        = 3'b000,
        SQ_STATE_VALID          = 3'b001,
        SQ_STATE_MHQ_FILL_WAIT  = 3'b010,
        SQ_STATE_NONSPECULATIVE = 3'b011,
        SQ_STATE_LAUNCHED       = 3'b100
    } sq_slot_state_t;

    // Each SQ slot contains:
    // lsu_func:        Indicates type of store op (SB, SH, SW)
    // addr:            Store address updated in ID stage
    // data:            Store data updated in ID stage
    // tag:             Destination tag in ROB (used for age comparison for store-to-load forwarding)
    // state:           Current state of the entry
    typedef struct packed {
        procyon_lsu_func_t                  lsu_func;
        procyon_addr_t                      addr;
        procyon_data_t                      data;
        procyon_tag_t                       tag;
        sq_slot_state_t                     state;
    } sq_slot_t;

/* verilator lint_off MULTIDRIVEN */
    sq_slot_t [`SQ_DEPTH-1:0]               sq_slots;
/* verilator lint_on  MULTIDRIVEN */
    sq_slot_state_t                         sq_slot_state_next [`SQ_DEPTH-1:0];
    logic                                   sq_full;
    procyon_sq_select_t                     sq_empty;
    procyon_sq_select_t                     sq_retirable;
    procyon_sq_select_t                     sq_rob_tag_match;
    procyon_sq_select_t                     sq_allocate_select;
    procyon_sq_select_t                     sq_rob_select;
    procyon_sq_select_t                     sq_update_select;
    procyon_sq_select_t                     sq_retire_select;
    sq_idx_t                                sq_retire_slot;
    logic                                   sq_retire_en;
    logic                                   sq_retire_ack;

    assign sq_allocate_select               = {(`SQ_DEPTH){i_alloc_en}} & (sq_empty & ~(sq_empty - 1'b1));
    assign sq_rob_select                    = {(`SQ_DEPTH){i_rob_retire_en}} & sq_rob_tag_match;
    assign sq_retire_select                 = {(`SQ_DEPTH){~i_sq_retire_stall}} & (sq_retirable & ~(sq_retirable - 1'b1));
    assign sq_update_select                 = {(`SQ_DEPTH){i_update_en}} & i_update_select;

    assign sq_retire_en                     = sq_retire_select != {(`SQ_DEPTH){1'b0}};
    assign sq_retire_ack                    = i_rob_retire_en & sq_retire_en & (sq_slots[sq_retire_slot].tag == i_rob_retire_tag);

    // Output full signal
    // FIXME: Can this be registered?
    assign sq_full                          = ((sq_empty & ~sq_allocate_select) == {(`SQ_DEPTH){1'b0}});
    assign o_full                           = sq_full;

    always_comb begin
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            // A slot is ready to be retired if it is non-speculative
            sq_retirable[i]     = (sq_slots[i].state == SQ_STATE_NONSPECULATIVE);

            // Match the ROB retire tag with an entry to determine which entry should be marked nonspeculative (i.e. retirable)
            // Only one valid slot should have the matching tag
            sq_rob_tag_match[i] = (sq_slots[i].tag == i_rob_retire_tag);

            // A slot is considered empty if it is invalid
            sq_empty[i]         = (sq_slots[i].state == SQ_STATE_INVALID);
        end
    end

    // Update state for each SQ entry
    always_comb begin
        sq_slot_state_t sq_fill_bypass_mux;
        sq_slot_state_t sq_update_state_mux;

        // Bypass fill broadcast if an update comes through on the same cycle as the fill
        sq_fill_bypass_mux  = i_mhq_fill_en ? SQ_STATE_NONSPECULATIVE : SQ_STATE_MHQ_FILL_WAIT;
        sq_update_state_mux = (i_update_retry & i_update_mhq_retry) ? sq_fill_bypass_mux : SQ_STATE_INVALID;

        for (int i = 0; i < `SQ_DEPTH; i++) begin
            sq_slot_state_next[i] = sq_slots[i].state;
            case (sq_slot_state_next[i])
                SQ_STATE_INVALID:        sq_slot_state_next[i] = sq_allocate_select[i] ? SQ_STATE_VALID : sq_slot_state_next[i];
                SQ_STATE_VALID:          sq_slot_state_next[i] = i_flush ? SQ_STATE_INVALID : (sq_rob_select[i] ? SQ_STATE_NONSPECULATIVE : sq_slot_state_next[i]);
                SQ_STATE_MHQ_FILL_WAIT:  sq_slot_state_next[i] = i_mhq_fill_en ? SQ_STATE_NONSPECULATIVE : sq_slot_state_next[i];
                SQ_STATE_NONSPECULATIVE: sq_slot_state_next[i] = sq_retire_select[i] ? SQ_STATE_LAUNCHED : sq_slot_state_next[i];
                SQ_STATE_LAUNCHED:       sq_slot_state_next[i] = sq_update_select[i] ? sq_update_state_mux : sq_slot_state_next[i];
                default:                 sq_slot_state_next[i] = SQ_STATE_INVALID;
            endcase
        end
    end

    // Convert one-hot retire_select vector into binary SQ slot #
    always_comb begin
        sq_retire_slot = {($clog2(`SQ_DEPTH)){1'b0}};
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            if (sq_retire_select[i]) begin
                sq_retire_slot = sq_idx_t'(i);
            end
        end
    end

    // Send ack back to ROB when launching the retired store
    always_ff @(posedge clk) begin
        if (~n_rst) o_rob_retire_ack <= 1'b0;
        else        o_rob_retire_ack <= sq_retire_ack;
    end

    // Retire stores to D$ or to the MHQ if it misses in the cache
    // The retiring store address and type and sq_retire_en signals is also sent to the LQ for possible load bypass violation detection
    always_ff @(posedge clk) begin
        if (~n_rst || i_flush)       o_sq_retire_en <= 1'b0;
        else if (~i_sq_retire_stall) o_sq_retire_en <= sq_retire_en;
    end

    always_ff @(posedge clk) begin
        if (~i_sq_retire_stall) begin
            o_sq_retire_data     <= sq_slots[sq_retire_slot].data;
            o_sq_retire_addr     <= sq_slots[sq_retire_slot].addr;
            o_sq_retire_tag      <= sq_slots[sq_retire_slot].tag;
            o_sq_retire_lsu_func <= sq_slots[sq_retire_slot].lsu_func;
            o_sq_retire_select   <= sq_retire_select;
        end
    end

    // Update slot for newly allocated store op
    always_ff @(posedge clk) begin
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            if (~n_rst) sq_slots[i].state <= SQ_STATE_INVALID;
            else        sq_slots[i].state <= sq_slot_state_next[i];
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            if (sq_allocate_select[i] & (sq_slots[i].state == SQ_STATE_INVALID)) begin
                sq_slots[i].data       <= i_alloc_data;
                sq_slots[i].addr       <= i_alloc_addr;
                sq_slots[i].lsu_func   <= i_alloc_lsu_func;
                sq_slots[i].tag        <= i_alloc_tag;
            end
        end
    end

endmodule
