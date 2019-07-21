// Load Queue
// Every cycle a new load op may be allocated in the load queue when issued from the reservation station
// Every cycle a load may be deallocated from the load queue when retired from the ROB
// Every cycle a stalled load can be replayed if the cacheline it was waiting for is returned from memory
// The purpose of the load queue is to keep track of load ops until they are retired and to detect
// mis-speculated loads whenever a store op has been retired

`include "common.svh"
import procyon_types::*;

module lsu_lq (
    input  logic                          clk,
    input  logic                          n_rst,

    input  logic                          i_flush,
    output logic                          o_full,

    // Signals from LSU_ID to allocate new load op
    input  logic                          i_alloc_en,
    input  procyon_lsu_func_t             i_alloc_lsu_func,
    input  procyon_tag_t                  i_alloc_tag,
    input  procyon_addr_t                 i_alloc_addr,
    output procyon_lq_select_t            o_alloc_lq_select,

    // Signals to LSU_EX for replaying loads
    input  logic                          i_replay_stall,
    output logic                          o_replay_en,
    output procyon_lq_select_t            o_replay_select,
    output procyon_lsu_func_t             o_replay_lsu_func,
    output procyon_addr_t                 o_replay_addr,
    output procyon_tag_t                  o_replay_tag,

    // Signals from LSU_EX and MHQ_LU to update a load when it needs replaying
    input  logic                          i_update_en,
    input  procyon_lq_select_t            i_update_select,
    input  logic                          i_update_retry,
    input  procyon_mhq_tag_t              i_update_mhq_tag,
    input  logic                          i_update_mhq_retry,

    // MHQ fill broadcast
    input  logic                          i_mhq_fill_en,
    input  procyon_mhq_tag_t              i_mhq_fill_tag,

    // SQ will send address of retiring store for mis-speculation detection
    input  logic                          i_sq_retire_en,
    input  procyon_addr_t                 i_sq_retire_addr,
    input  procyon_lsu_func_t             i_sq_retire_lsu_func,

    // ROB signal that a load has been retired
    input  logic                          i_rob_retire_en,
    input  procyon_tag_t                  i_rob_retire_tag,
    output logic                          o_rob_retire_ack,
    output logic                          o_rob_retire_misspeculated
);

    typedef logic [`LQ_TAG_WIDTH-1:0]     lq_idx_t;

    // Each entry in the LQ can be in one of the following states
    // INVALID: Slot is empty
    // VALID:   Slot is occupied with a load op and is currently going through the LSU pipeline
    // MHQ_TAG_WAIT: Slot contains a load op that missed in the cache but allocated in the MHQ and must wait for the MHQ to fill the cacheline being replayed
    // MHQ_FILL_WAIT: Slot contains a load op that missed in the cache and could not allocate in the MHQ and must wait for the MHQ fill any cacheline before being replayed
    // REPLAYABLE:    Slot contains a load op that is woken up due to a MHQ fill broadcast and can be replayed
    // LAUNCHED:      Slot contains a load op that has been replayed and is currently going through the LSU pipeline and must wait for the LSU update
    // COMPLETE:      Slot contains a load op that has successfully been executed and is waiting for ROB retire signal before it can be dequeued
    typedef enum logic [2:0] {
        LQ_STATE_INVALID       = 3'b000,
        LQ_STATE_VALID         = 3'b001,
        LQ_STATE_MHQ_TAG_WAIT  = 3'b010,
        LQ_STATE_MHQ_FILL_WAIT = 3'b011,
        LQ_STATE_REPLAYABLE    = 3'b100,
        LQ_STATE_LAUNCHED      = 3'b101,
        LQ_STATE_COMPLETE      = 3'b110
    } lq_slot_state_t;

    // Each entry in the LQ contains the following
    // addr:              The load address
    // tag:               ROB tag used to determine age of the load op
    // lsu_func:          LSU op i.e. LB, LH, LW, LBU, LHU
    // mhq_tag:           MHQ tag it is waiting on for replay when the load misses in the cache
    // misspeculated:     Indicates whether the load has been potentially incorrectly speculately executed (when a retiring store hits in the address range of the load)
    // state:             Current state of the entry
    typedef struct packed {
        procyon_addr_t                    addr;
        procyon_tag_t                     tag;
        procyon_lsu_func_t                lsu_func;
        procyon_mhq_tag_t                 mhq_tag;
        logic                             misspeculated;
        lq_slot_state_t                   state;
    } lq_slot_t;

/* verilator lint_off MULTIDRIVEN */
    lq_slot_t [`LQ_DEPTH-1:0]             lq_slots;
/* verilator lint_on  MULTIDRIVEN */
    lq_slot_state_t                       lq_slot_state_next [`LQ_DEPTH-1:0];
    logic                                 lq_full;
    procyon_lq_select_t                   lq_empty;
    procyon_lq_select_t                   lq_replayable;
    procyon_lq_select_t                   lq_allocate_select;
    procyon_lq_select_t                   lq_update_select;
    procyon_lq_select_t                   lq_replay_select;
    procyon_lq_select_t                   lq_mhq_tag_select;
    procyon_lq_select_t                   lq_retire_select;
    procyon_lq_select_t                   lq_misspeculated_select;
    logic                                 lq_replay_en;
    lq_idx_t                              lq_retire_slot;
    lq_idx_t                              lq_replay_slot;
    logic                                 lq_retire_ack;

    assign lq_allocate_select             = {(`LQ_DEPTH){i_alloc_en}} & (lq_empty & ~(lq_empty - 1'b1));
    assign lq_update_select               = {(`LQ_DEPTH){i_update_en}} & i_update_select;
    assign lq_replay_select               = {(`LQ_DEPTH){~i_replay_stall}} & (lq_replayable & ~(lq_replayable - 1'b1));

    assign lq_replay_en                   = (lq_replay_select != {(`LQ_DEPTH){1'b0}});
    assign lq_retire_ack                  = i_rob_retire_en & (lq_slots[lq_retire_slot].state == LQ_STATE_COMPLETE);

    // Ouput full-on-next-cycle signal (i.e. The last entry will be allocated on this cycle means it will be full on the next cycle)
    // FIXME: Can this be registered
    assign lq_full                        = ((lq_empty & ~lq_allocate_select) == {(`LQ_DEPTH){1'b0}});
    assign o_full                         = lq_full;

    // Calculate misspeculated bit based off of overlapping load and retiring store addresses
    always_comb begin
        procyon_addr_t sq_retire_addr_end;

        case (i_sq_retire_lsu_func)
            LSU_FUNC_SB: sq_retire_addr_end = i_sq_retire_addr + procyon_addr_t'(1);
            LSU_FUNC_SH: sq_retire_addr_end = i_sq_retire_addr + procyon_addr_t'(2);
            LSU_FUNC_SW: sq_retire_addr_end = i_sq_retire_addr + procyon_addr_t'(4);
            default:     sq_retire_addr_end = i_sq_retire_addr + procyon_addr_t'(4);
        endcase

        for (int i = 0; i < `LQ_DEPTH; i++) begin
            procyon_addr_t lq_addr_end;
            logic          lq_overlap_sq;
            logic          sq_overlap_lq;

            case (lq_slots[i].lsu_func)
                LSU_FUNC_LB:  lq_addr_end = lq_slots[i].addr + procyon_addr_t'(1);
                LSU_FUNC_LH:  lq_addr_end = lq_slots[i].addr + procyon_addr_t'(2);
                LSU_FUNC_LBU: lq_addr_end = lq_slots[i].addr + procyon_addr_t'(1);
                LSU_FUNC_LHU: lq_addr_end = lq_slots[i].addr + procyon_addr_t'(2);
                default:      lq_addr_end = lq_slots[i].addr + procyon_addr_t'(4);
            endcase

            // Compare retired store address with all valid load addresses to detect mis-speculated loads
            lq_overlap_sq              = (lq_slots[i].addr >= i_sq_retire_addr) & (lq_slots[i].addr < sq_retire_addr_end);
            sq_overlap_lq              = (i_sq_retire_addr >= lq_slots[i].addr) & (i_sq_retire_addr < lq_addr_end);
            lq_misspeculated_select[i] = i_sq_retire_en & (lq_overlap_sq | sq_overlap_lq);
        end
    end

    always_comb begin
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            lq_replayable[i]           = (lq_slots[i].state == LQ_STATE_REPLAYABLE);

            // Compare MHQ tags with the MHQ fill broadcast tag to determine which loads can be replayed
            lq_mhq_tag_select[i]       = i_mhq_fill_en & (lq_slots[i].mhq_tag == i_mhq_fill_tag);

            // Use the ROB tag to determine which slot will be retired by generating a retire_select one-hot bit vector
            // Only one valid slot should have the matching tag
            lq_retire_select[i]        = i_rob_retire_en & (lq_slots[i].tag == i_rob_retire_tag) && (lq_slots[i].state != LQ_STATE_INVALID);

            // A slot is considered empty if it is invalid
            lq_empty[i]                = (lq_slots[i].state == LQ_STATE_INVALID);
        end
    end

    always_comb begin
        lq_slot_state_t lq_update_state_mux;
        lq_slot_state_t lq_fill_bypass_mux;

        // Bypass fill broadcast if an update comes through on the same cycle with an mhq_tag that matches the fill tag
        lq_fill_bypass_mux  = ((i_mhq_fill_en & (i_update_mhq_tag == i_mhq_fill_tag)) ? LQ_STATE_REPLAYABLE : LQ_STATE_MHQ_TAG_WAIT);
        lq_update_state_mux = lq_slot_state_t'(mux4_3b(LQ_STATE_COMPLETE, lq_fill_bypass_mux, LQ_STATE_COMPLETE, LQ_STATE_MHQ_FILL_WAIT, {i_update_mhq_retry, i_update_retry}));
        for (int i = 0; i < `SQ_DEPTH; i++) begin
            lq_slot_state_next[i] = lq_slots[i].state;
            case (lq_slot_state_next[i])
                LQ_STATE_INVALID:       lq_slot_state_next[i] = lq_allocate_select[i] ? LQ_STATE_VALID : lq_slot_state_next[i];
                LQ_STATE_VALID:         lq_slot_state_next[i] = lq_update_select[i] ? lq_update_state_mux : lq_slot_state_next[i];
                LQ_STATE_MHQ_TAG_WAIT:  lq_slot_state_next[i] = lq_mhq_tag_select[i] ? LQ_STATE_REPLAYABLE : lq_slot_state_next[i];
                LQ_STATE_MHQ_FILL_WAIT: lq_slot_state_next[i] = i_mhq_fill_en ? LQ_STATE_REPLAYABLE : lq_slot_state_next[i];
                LQ_STATE_REPLAYABLE:    lq_slot_state_next[i] = lq_replay_select[i] ? LQ_STATE_LAUNCHED : lq_slot_state_next[i];
                LQ_STATE_LAUNCHED:      lq_slot_state_next[i] = lq_update_select[i] ? lq_update_state_mux : lq_slot_state_next[i];
                LQ_STATE_COMPLETE:      lq_slot_state_next[i] = lq_retire_select[i] ? LQ_STATE_INVALID : lq_slot_state_next[i];
                default:                lq_slot_state_next[i] = LQ_STATE_INVALID;
            endcase
        end
    end

    // Convert one-hot retire_select vector into binary LQ slot #
    always_comb begin
        lq_retire_slot = {(`LQ_TAG_WIDTH){1'b0}};
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (lq_retire_select[i]) begin
                lq_retire_slot = lq_idx_t'(i);
            end
        end
    end

    // Convert one-hot replay_select vector into binary LQ slot #
    always_comb begin
        lq_replay_slot = {(`LQ_TAG_WIDTH){1'b0}};
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (lq_replay_select[i]) begin
                lq_replay_slot = lq_idx_t'(i);
            end
        end
    end

    // Let ROB know that retired load was mis-speculated
    always_ff @(posedge clk) begin
        o_rob_retire_misspeculated <= lq_slots[lq_retire_slot].misspeculated;
    end

    // Send ack back to ROB with mis-speculated signal when ROB indicates load to be retired
    always_ff @(posedge clk) begin
        if (~n_rst) o_rob_retire_ack <= 1'b0;
        else        o_rob_retire_ack <= lq_retire_ack;
    end

    // Output replaying load
    always_ff @(posedge clk) begin
        if (~n_rst || i_flush)    o_replay_en <= 1'b0;
        else if (~i_replay_stall) o_replay_en <= lq_replay_en;
    end

    always_ff @(posedge clk) begin
        if (~i_replay_stall) begin
            o_replay_select    <= lq_replay_select;
            o_replay_lsu_func  <= lq_slots[lq_replay_slot].lsu_func;
            o_replay_addr      <= lq_slots[lq_replay_slot].addr;
            o_replay_tag       <= lq_slots[lq_replay_slot].tag;
        end
    end

    // Output LQ select vector on allocate request
    always_ff @(posedge clk) begin
        o_alloc_lq_select <= lq_allocate_select;
    end

    // Update slot for newly allocated load op
    always_ff @(posedge clk) begin
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (~n_rst || i_flush) lq_slots[i].state <= LQ_STATE_INVALID;
            else                   lq_slots[i].state <= lq_slot_state_next[i];
        end
    end

    // Update misspeculated bit depending on state; it is cleared if we enter LQ_STATE_MHQ_TAG_WAIT, LQ_STATE_MHQ_FILL_WAIT or LQ_STATE_REPLAYABLE or if the entry is being allocated
    // since we know the load hasn't forwarded the incorrect data over the CDB. It is set when the retiring store matches the loads address range
    always_ff @(posedge clk) begin
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            lq_slots[i].mhq_tag         <= lq_update_select[i] ? i_update_mhq_tag : lq_slots[i].mhq_tag;
            lq_slots[i].misspeculated   <= ~(lq_allocate_select[i] | (lq_slots[i].state == LQ_STATE_MHQ_TAG_WAIT) | (lq_slots[i].state == LQ_STATE_MHQ_FILL_WAIT) | (lq_slots[i].state == LQ_STATE_REPLAYABLE)) & (lq_misspeculated_select[i] | lq_slots[i].misspeculated);
            if (lq_allocate_select[i] & (lq_slots[i].state == LQ_STATE_INVALID)) begin
                lq_slots[i].addr        <= i_alloc_addr;
                lq_slots[i].tag         <= i_alloc_tag;
                lq_slots[i].lsu_func    <= i_alloc_lsu_func;
            end
        end
    end

endmodule
