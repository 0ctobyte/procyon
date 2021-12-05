/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

`include "procyon_constants.svh"

module procyon_lsu_sq_entry #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_flush,

    output logic                            o_empty,
    output logic                            o_retirable,
    output logic                            o_nonspeculative,

    // Signals from LSU_ID to allocate new store op in SQ
    input  logic                            i_alloc_en,
    input  logic [`PCYN_OP_WIDTH-1:0]       i_alloc_op,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_alloc_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_alloc_addr,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_alloc_data,

    // Send out store to LSU on retirement and to the load queue for detection of mis-speculated loads
    input  logic                            i_retire_en,
    output logic [`PCYN_OP_WIDTH-1:0]       o_retire_op,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_retire_tag,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_retire_addr,
    output logic [OPTN_DATA_WIDTH-1:0]      o_retire_data,

    // Signals from the LSU and MHQ to indicate if the last retiring store needs to be retried later or replayed ASAP
    input  logic                            i_update_en,
    input  logic                            i_update_retry,
    input  logic                            i_update_replay,
    input  logic                            i_update_mhq_retry,
    input  logic                            i_update_mhq_replay,

    // MHQ fill interface for waking up waiting stores
    input  logic                            i_mhq_fill_en,

    // ROB signal that a store has been retired
    input  logic                            i_rob_retire_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_rob_retire_tag,
    output logic                            o_rob_retire_ack
);

    // Each SQ entry is in one of the following states:
    // INVALID:        Entry is empty
    // VALID:          Entry contains a valid but not retired store operation
    // MHQ_FILL_WAIT:  Entry contains a store op that is waiting for an MHQ fill broadcast
    // NONSPECULATIVE: Entry contains a store that is at the head of the ROB and thus is ready to be retired
    // LAUNCHED:       Entry contains a retired store that has been launched into the LSU pipeline
    //                 It must wait in this state until the LSU indicates if it was retired successfully or if it needs to be relaunched
    localparam SQ_ENTRY_STATE_WIDTH = 3;

    typedef enum logic [SQ_ENTRY_STATE_WIDTH-1:0] {
        SQ_ENTRY_STATE_INVALID        = 3'b000,
        SQ_ENTRY_STATE_VALID          = 3'b001,
        SQ_ENTRY_STATE_MHQ_FILL_WAIT  = 3'b100,
        SQ_ENTRY_STATE_NONSPECULATIVE = 3'b101,
        SQ_ENTRY_STATE_LAUNCHED       = 3'b110
    } sq_entry_state_t;

    // Each SQ entry contains:
    // op:              Indicates type of store op (SB, SH, SW)
    // addr:            Store address updated in ID stage
    // data:            Store data updated in ID stage
    // tag:             Destination tag in ROB (used for age comparison for store-to-load forwarding)
    // state:           Current state of the entry
    logic [`PCYN_OP_WIDTH-1:0] sq_entry_op_r;
    logic [OPTN_ADDR_WIDTH-1:0] sq_entry_addr_r;
    logic [OPTN_DATA_WIDTH-1:0] sq_entry_data_r;
    logic [OPTN_ROB_IDX_WIDTH-1:0] sq_entry_tag_r;
    sq_entry_state_t sq_entry_state_r;

    // Determine if this entry is being retired from the ROB
    // Match the ROB retire tag with the entry to determine if the entry should be marked nonspeculative (i.e. retirable)
    // Only one valid entry should have the matching tag
    logic rob_retire_en;
    assign rob_retire_en = i_rob_retire_en & (sq_entry_tag_r == i_rob_retire_tag) & (sq_entry_state_r == SQ_ENTRY_STATE_VALID);

    // SQ entry FSM
    sq_entry_state_t sq_entry_state_next;

    always_comb begin
        sq_entry_state_t sq_fill_bypass_mux;
        sq_entry_state_t sq_update_state_mux;
        logic [2:0] sq_update_state_sel;

        // Bypass fill broadcast if an update comes through on the same cycle as the fill
        // i_update_replay is asserted if a fill address conflicted on the LSU_DT or LSU_DW stages. The op just needs to be replayed ASAP
        sq_fill_bypass_mux = i_mhq_fill_en ? SQ_ENTRY_STATE_NONSPECULATIVE : SQ_ENTRY_STATE_MHQ_FILL_WAIT;
        sq_update_state_sel = {i_update_retry, i_update_mhq_replay | i_update_replay, i_update_mhq_retry};

        case (sq_update_state_sel)
            3'b000: sq_update_state_mux = SQ_ENTRY_STATE_INVALID;
            3'b001: sq_update_state_mux = SQ_ENTRY_STATE_INVALID;
            3'b010: sq_update_state_mux = SQ_ENTRY_STATE_INVALID;
            3'b011: sq_update_state_mux = SQ_ENTRY_STATE_INVALID;
            3'b100: sq_update_state_mux = SQ_ENTRY_STATE_INVALID;
            3'b101: sq_update_state_mux = sq_fill_bypass_mux;
            3'b110: sq_update_state_mux = SQ_ENTRY_STATE_NONSPECULATIVE;
            3'b111: sq_update_state_mux = SQ_ENTRY_STATE_NONSPECULATIVE;
        endcase

        sq_entry_state_next = sq_entry_state_r;

        case (sq_entry_state_next)
            SQ_ENTRY_STATE_INVALID:        sq_entry_state_next = i_alloc_en ? SQ_ENTRY_STATE_VALID : sq_entry_state_next;
            SQ_ENTRY_STATE_VALID:          sq_entry_state_next = i_flush ? SQ_ENTRY_STATE_INVALID : (rob_retire_en ? SQ_ENTRY_STATE_NONSPECULATIVE : sq_entry_state_next);
            SQ_ENTRY_STATE_MHQ_FILL_WAIT:  sq_entry_state_next = i_mhq_fill_en ? SQ_ENTRY_STATE_NONSPECULATIVE : sq_entry_state_next;
            SQ_ENTRY_STATE_NONSPECULATIVE: sq_entry_state_next = i_retire_en ? SQ_ENTRY_STATE_LAUNCHED : sq_entry_state_next;
            SQ_ENTRY_STATE_LAUNCHED:       sq_entry_state_next = i_flush ? SQ_ENTRY_STATE_NONSPECULATIVE : (i_update_en ? sq_update_state_mux : sq_entry_state_next);
            default:                       sq_entry_state_next = SQ_ENTRY_STATE_INVALID;
        endcase
    end

    procyon_srff #(SQ_ENTRY_STATE_WIDTH) sq_entry_state_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(sq_entry_state_next), .i_reset(SQ_ENTRY_STATE_INVALID), .o_q(sq_entry_state_r));

    procyon_ff #(`PCYN_OP_WIDTH) sq_entry_op_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_op), .o_q(sq_entry_op_r));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) sq_entry_tag_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_tag), .o_q(sq_entry_tag_r));
    procyon_ff #(OPTN_ADDR_WIDTH) sq_entry_addr_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_addr), .o_q(sq_entry_addr_r));
    procyon_ff #(OPTN_DATA_WIDTH) sq_entry_data_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_data), .o_q(sq_entry_data_r));

    // Output empty status for this entry
    assign o_empty = (sq_entry_state_r == SQ_ENTRY_STATE_INVALID);

    // The entry is ready to be retired if it is in the nonspeculative state
    assign o_retirable = (sq_entry_state_r == SQ_ENTRY_STATE_NONSPECULATIVE);

    // The entry is nonspeculative if it is in the nonspeculative, mhq_fill_wait or launched states
    assign o_nonspeculative = sq_entry_state_r[SQ_ENTRY_STATE_WIDTH-1];

    // Output signals for retiring the store
    assign o_retire_op = sq_entry_op_r;
    assign o_retire_tag = sq_entry_tag_r;
    assign o_retire_addr = sq_entry_addr_r;
    assign o_retire_data = sq_entry_data_r;

    // ROB retire ack
    assign o_rob_retire_ack = rob_retire_en;

endmodule


