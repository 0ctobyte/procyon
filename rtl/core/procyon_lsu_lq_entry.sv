/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

`include "procyon_constants.svh"

module procyon_lsu_lq_entry #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5,
    parameter OPTN_MHQ_IDX_WIDTH = 2

)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_flush,

    output logic                            o_empty,
    output logic                            o_replayable,

    // Signals from LSU_ID to allocate new load op
    input  logic                            i_alloc_en,
    input  logic [`PCYN_OP_WIDTH-1:0]       i_alloc_op,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_alloc_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_alloc_addr,

    // Output signals to replay this load
    input  logic                            i_replay_en,
    output logic [`PCYN_OP_WIDTH-1:0]       o_replay_op,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_replay_tag,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_replay_addr,

    // Signals from LSU_EX and MHQ_LU to update a load when it needs to be retried later or replayed ASAP
    input  logic                            i_update_en,
    input  logic                            i_update_retry,
    input  logic                            i_update_replay,
    input  logic [OPTN_MHQ_IDX_WIDTH-1:0]   i_update_mhq_tag,
    input  logic                            i_update_mhq_retry,
    input  logic                            i_update_mhq_replay,

    // MHQ fill broadcast
    input  logic                            i_mhq_fill_en,
    input  logic [OPTN_MHQ_IDX_WIDTH-1:0]   i_mhq_fill_tag,

    // SQ will send address of retiring store for mis-speculation detection
    input  logic                            i_sq_retire_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_sq_retire_addr,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_sq_retire_addr_end,

    // ROB signal that a load has been retired
    input  logic                            i_rob_retire_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_rob_retire_tag,
    output logic                            o_rob_retire_ack,
    output logic                            o_rob_retire_misspeculated
);

    localparam DATA_SIZE = OPTN_DATA_WIDTH / 8;

    // Each entry in the LQ can be in one of the following states
    // INVALID:       Entry is empty
    // VALID:         Entry is occupied with a load op and is currently going through the LSU pipeline
    // MHQ_TAG_WAIT:  Entry contains a load op that missed in the cache but allocated in the MHQ and must wait for the MHQ to fill the cacheline being replayed
    // MHQ_FILL_WAIT: Entry contains a load op that missed in the cache and could not allocate in the MHQ and must wait for the MHQ fill any cacheline before being replayed
    // REPLAYABLE:    Entry contains a load op that is woken up due to a MHQ fill broadcast and can be replayed
    // LAUNCHED:      Entry contains a load op that has been replayed and is currently going through the LSU pipeline and must wait for the LSU update
    // COMPLETE:      Entry contains a load op that has successfully been executed and is waiting for ROB retire signal before it can be dequeued
    localparam LQ_ENTRY_STATE_WIDTH = 3;

    typedef enum logic [LQ_ENTRY_STATE_WIDTH-1:0] {
        LQ_ENTRY_STATE_INVALID       = 3'b000,
        LQ_ENTRY_STATE_VALID         = 3'b001,
        LQ_ENTRY_STATE_MHQ_TAG_WAIT  = 3'b010,
        LQ_ENTRY_STATE_MHQ_FILL_WAIT = 3'b011,
        LQ_ENTRY_STATE_REPLAYABLE    = 3'b100,
        LQ_ENTRY_STATE_LAUNCHED      = 3'b101,
        LQ_ENTRY_STATE_COMPLETE      = 3'b110
    } lq_entry_state_t;

    // Each entry in the LQ contains the following
    // addr:              The load address
    // tag:               ROB tag used to determine age of the load op
    // op:                LSU op i.e. LB, LH, LW, LBU, LHU, SB, SH, SW
    // mhq_tag:           MHQ tag it is waiting on for replay when the load misses in the cache
    // misspeculated:     Indicates whether the load has been potentially incorrectly speculately executed (when a retiring store hits in the address range of the load)
    // state:             Current state of the entry
    logic [OPTN_ADDR_WIDTH-1:0] lq_entry_addr_r;
    logic [OPTN_ROB_IDX_WIDTH-1:0] lq_entry_tag_r;
    logic [`PCYN_OP_WIDTH-1:0] lq_entry_op_r;
    logic [OPTN_MHQ_IDX_WIDTH-1:0] lq_entry_mhq_tag_r;
    logic lq_entry_misspeculated_r;
    lq_entry_state_t lq_entry_state_r;

    // Determine if this entry is being retired
    logic retire_en;
    assign retire_en = i_rob_retire_en & (lq_entry_tag_r == i_rob_retire_tag) & (lq_entry_state_r == LQ_ENTRY_STATE_COMPLETE);

    // LQ entry FSM
    lq_entry_state_t lq_entry_state_next;

    always_comb begin
        lq_entry_state_t lq_update_state_mux;
        lq_entry_state_t lq_fill_tag_bypass_mux;
        lq_entry_state_t lq_fill_bypass_mux;
        logic [2:0] lq_update_state_sel;
        logic lq_mhq_tag_match;

        // Compare MHQ tags with the MHQ fill broadcast tag to determine which loads can be replayed
        lq_mhq_tag_match = i_mhq_fill_en & (lq_entry_mhq_tag_r == i_mhq_fill_tag);

        // Bypass fill broadcast if an update comes through on the same cycle with an mhq_tag that matches the fill tag
        // i_update_replay is asserted if a fill address conflicted on the LSU_DT or LSU_DW stages. The op just needs to be replayed ASAP
        lq_fill_tag_bypass_mux = ((i_mhq_fill_en & (i_update_mhq_tag == i_mhq_fill_tag)) ? LQ_ENTRY_STATE_REPLAYABLE : LQ_ENTRY_STATE_MHQ_TAG_WAIT);
        lq_fill_bypass_mux = i_mhq_fill_en ? LQ_ENTRY_STATE_REPLAYABLE : LQ_ENTRY_STATE_MHQ_FILL_WAIT;
        lq_update_state_sel = {i_update_retry, i_update_mhq_replay | i_update_replay, i_update_mhq_retry};

        case (lq_update_state_sel)
            3'b000: lq_update_state_mux = LQ_ENTRY_STATE_COMPLETE;
            3'b001: lq_update_state_mux = LQ_ENTRY_STATE_COMPLETE;
            3'b010: lq_update_state_mux = LQ_ENTRY_STATE_COMPLETE;
            3'b011: lq_update_state_mux = LQ_ENTRY_STATE_COMPLETE;
            3'b100: lq_update_state_mux = lq_fill_tag_bypass_mux;
            3'b101: lq_update_state_mux = lq_fill_bypass_mux;
            3'b110: lq_update_state_mux = LQ_ENTRY_STATE_REPLAYABLE;
            3'b111: lq_update_state_mux = LQ_ENTRY_STATE_REPLAYABLE;
        endcase

        lq_entry_state_next = lq_entry_state_r;

        case (lq_entry_state_next)
            LQ_ENTRY_STATE_INVALID:       lq_entry_state_next = i_alloc_en ? LQ_ENTRY_STATE_VALID : lq_entry_state_next;
            LQ_ENTRY_STATE_VALID:         lq_entry_state_next = i_update_en ? lq_update_state_mux : lq_entry_state_next;
            LQ_ENTRY_STATE_MHQ_TAG_WAIT:  lq_entry_state_next = lq_mhq_tag_match ? LQ_ENTRY_STATE_REPLAYABLE : lq_entry_state_next;
            LQ_ENTRY_STATE_MHQ_FILL_WAIT: lq_entry_state_next = i_mhq_fill_en ? LQ_ENTRY_STATE_REPLAYABLE : lq_entry_state_next;
            LQ_ENTRY_STATE_REPLAYABLE:    lq_entry_state_next = i_replay_en ? LQ_ENTRY_STATE_LAUNCHED : lq_entry_state_next;
            LQ_ENTRY_STATE_LAUNCHED:      lq_entry_state_next = i_update_en ? lq_update_state_mux : lq_entry_state_next;
            LQ_ENTRY_STATE_COMPLETE:      lq_entry_state_next = retire_en ? LQ_ENTRY_STATE_INVALID : lq_entry_state_next;
            default:                      lq_entry_state_next = LQ_ENTRY_STATE_INVALID;
        endcase

        lq_entry_state_next = i_flush ? LQ_ENTRY_STATE_INVALID : lq_entry_state_next;
    end

    procyon_srff #(LQ_ENTRY_STATE_WIDTH) lq_entry_state_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(lq_entry_state_next), .i_reset(LQ_ENTRY_STATE_INVALID), .o_q(lq_entry_state_r));

    // Calculate misspeculated bit based off of overlapping load and retiring store addresses. We need to perform this check
    // for allocating loads in case the store is retiring on the same cycle as the allocation.
    logic lq_entry_misspeculated;

    always_comb begin
        logic [`PCYN_OP_WIDTH-1:0] lq_op;
        logic [OPTN_ADDR_WIDTH-1:0] lq_addr_start;
        logic [OPTN_ADDR_WIDTH-1:0] lq_addr_end;
        logic lq_overlap_sq;
        logic sq_overlap_lq;
        logic overlap_detected;

        lq_op = i_alloc_en ? i_alloc_op : lq_entry_op_r;
        lq_addr_start = i_alloc_en ? i_alloc_addr : lq_entry_addr_r;

        case (lq_op)
            `PCYN_OP_LB:  lq_addr_end = lq_addr_start + OPTN_ADDR_WIDTH'(1);
            `PCYN_OP_LH:  lq_addr_end = lq_addr_start + OPTN_ADDR_WIDTH'(DATA_SIZE/2);
            `PCYN_OP_LBU: lq_addr_end = lq_addr_start + OPTN_ADDR_WIDTH'(1);
            `PCYN_OP_LHU: lq_addr_end = lq_addr_start + OPTN_ADDR_WIDTH'(DATA_SIZE/2);
            default:      lq_addr_end = lq_addr_start + OPTN_ADDR_WIDTH'(DATA_SIZE);
        endcase

        // Compare retired store address with all valid load addresses to detect mis-speculated loads
        lq_overlap_sq = (lq_addr_start >= i_sq_retire_addr) & (lq_addr_start < i_sq_retire_addr_end);
        sq_overlap_lq = (i_sq_retire_addr >= lq_addr_start) & (i_sq_retire_addr < lq_addr_end);
        overlap_detected = i_sq_retire_en & (lq_overlap_sq | sq_overlap_lq);

        // Update misspeculated bit depending on state; it is cleared if we enter LQ_ENTRY_STATE_MHQ_TAG_WAIT, LQ_ENTRY_STATE_MHQ_FILL_WAIT or LQ_ENTRY_STATE_REPLAYABLE
        // since we know the load hasn't forwarded the incorrect data over the CDB. It is set when the retiring store matches the loads address range
        // We also need to clear the bit when the entry is being allocated and there is no overlap with a same-cycle retiring store
        lq_entry_misspeculated = ~((lq_entry_state_r == LQ_ENTRY_STATE_MHQ_TAG_WAIT) | (lq_entry_state_r == LQ_ENTRY_STATE_MHQ_FILL_WAIT) | (lq_entry_state_r == LQ_ENTRY_STATE_REPLAYABLE)) & (overlap_detected | (~i_alloc_en & lq_entry_misspeculated_r));
    end

    procyon_ff #(1) lq_entry_misspeculated_r_ff (.clk(clk), .i_en(1'b1), .i_d(lq_entry_misspeculated), .o_q(lq_entry_misspeculated_r));

    // Update the MHQ tag for the LQ entry
    logic [OPTN_MHQ_IDX_WIDTH-1:0] lq_entry_mhq_tag;
    assign lq_entry_mhq_tag = i_update_en ? i_update_mhq_tag : lq_entry_mhq_tag_r;
    procyon_ff #(OPTN_MHQ_IDX_WIDTH) lq_entry_mhq_tag_r_ff (.clk(clk), .i_en(1'b1), .i_d(lq_entry_mhq_tag), .o_q(lq_entry_mhq_tag_r));

    procyon_ff #(`PCYN_OP_WIDTH) lq_entry_op_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_op), .o_q(lq_entry_op_r));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) lq_entry_tag_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_tag), .o_q(lq_entry_tag_r));
    procyon_ff #(OPTN_ADDR_WIDTH) lq_entry_addr_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_addr), .o_q(lq_entry_addr_r));

    // Output empty status for this entry
    assign o_empty = (lq_entry_state_r == LQ_ENTRY_STATE_INVALID);

    // Check if the state is LQ_ENTRY_STATE_REPLAYABLE
    assign o_replayable = (lq_entry_state_r == LQ_ENTRY_STATE_REPLAYABLE);

    // Output signals for replays
    assign o_replay_op = lq_entry_op_r;
    assign o_replay_addr = lq_entry_addr_r;
    assign o_replay_tag = lq_entry_tag_r;

    // ROB retire interface
    assign o_rob_retire_ack = retire_en;
    assign o_rob_retire_misspeculated = lq_entry_misspeculated_r;

endmodule
