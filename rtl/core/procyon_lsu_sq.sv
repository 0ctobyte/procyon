/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Store Queue
// Every cycle a new store op may be allocated in the store queue when issued from the reservation station
// Every cycle a store may be launched to memory from the store queue after being retired from the ROB
// The purpose of the store queue is to keep track of store ops and commit them to memory in program order
// and to detect mis-speculated loads in the load queue

`include "procyon_constants.svh"

module procyon_lsu_sq #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_SQ_DEPTH      = 8,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_flush,
    output logic                            o_full,

    // Signals from LSU_ID to allocate new store op in SQ
    input  logic                            i_alloc_en,
    input  logic [`PCYN_OP_WIDTH-1:0]       i_alloc_op,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_alloc_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_alloc_addr,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_alloc_data,

    // Send out store to LSU on retirement and to the load queue for
    // detection of mis-speculated loads
    input  logic                            i_sq_retire_stall,
    output logic                            o_sq_retire_en,
    output logic [OPTN_SQ_DEPTH-1:0]        o_sq_retire_select,
    output logic [`PCYN_OP_WIDTH-1:0]       o_sq_retire_op,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_sq_retire_addr,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_sq_retire_tag,
    output logic [OPTN_DATA_WIDTH-1:0]      o_sq_retire_data,

    // Signals from the LSU and MHQ to indicate if the last retiring store needs to be retried later or replayed ASAP
    input  logic                            i_update_en,
    input  logic [OPTN_SQ_DEPTH-1:0]        i_update_select,
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

    localparam SQ_IDX_WIDTH = OPTN_SQ_DEPTH == 1 ? 1 : $clog2(OPTN_SQ_DEPTH);

    logic [OPTN_SQ_DEPTH-1:0] sq_entry_empty;
    logic [OPTN_SQ_DEPTH-1:0] sq_entry_retirable;
    logic [OPTN_SQ_DEPTH-1:0] sq_allocate_select;
    logic [OPTN_SQ_DEPTH-1:0] sq_update_select;
    logic [OPTN_SQ_DEPTH-1:0] sq_retire_select;
    logic [`PCYN_OP_WIDTH-1:0] sq_retire_op [0:OPTN_SQ_DEPTH-1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] sq_retire_tag [0:OPTN_SQ_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0] sq_retire_addr [0:OPTN_SQ_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0] sq_retire_data [0:OPTN_SQ_DEPTH-1];
    logic [OPTN_SQ_DEPTH-1:0] sq_rob_retire_ack;

    genvar inst;
    generate
    for (inst = 0; inst < OPTN_SQ_DEPTH; inst++) begin : GEN_LSU_SQ_ENTRY_INST
        procyon_lsu_sq_entry #(
            .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
            .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
            .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
        ) procyon_lsu_sq_entry_inst (
            .clk(clk),
            .n_rst(n_rst),
            .i_flush(i_flush),
            .o_empty(sq_entry_empty[inst]),
            .o_retirable(sq_entry_retirable[inst]),
            .i_alloc_en(sq_allocate_select[inst]),
            .i_alloc_op(i_alloc_op),
            .i_alloc_tag(i_alloc_tag),
            .i_alloc_addr(i_alloc_addr),
            .i_alloc_data(i_alloc_data),
            .i_retire_en(sq_retire_select[inst]),
            .o_retire_op(sq_retire_op[inst]),
            .o_retire_tag(sq_retire_tag[inst]),
            .o_retire_addr(sq_retire_addr[inst]),
            .o_retire_data(sq_retire_data[inst]),
            .i_update_en(sq_update_select[inst]),
            .i_update_retry(i_update_retry),
            .i_update_replay(i_update_replay),
            .i_update_mhq_retry(i_update_mhq_retry),
            .i_update_mhq_replay(i_update_mhq_replay),
            .i_mhq_fill_en(i_mhq_fill_en),
            .i_rob_retire_en(i_rob_retire_en),
            .i_rob_retire_tag(i_rob_retire_tag),
            .o_rob_retire_ack(sq_rob_retire_ack[inst])
        );
    end
    endgenerate

    // One hot vector indicating which SQ entry needs to be updated
    assign sq_update_select = {(OPTN_SQ_DEPTH){i_update_en}} & i_update_select;

    // Find an empty SQ entry that can be used to allocate a new store
    logic [OPTN_SQ_DEPTH-1:0] sq_allocate_picked;
    procyon_priority_picker #(OPTN_SQ_DEPTH) sq_allocate_picked_priority_picker (.i_in(sq_entry_empty), .o_pick(sq_allocate_picked));
    assign sq_allocate_select = {(OPTN_SQ_DEPTH){i_alloc_en}} & sq_allocate_picked;

    // Output full signal
    assign o_full = ((sq_entry_empty & ~sq_allocate_select) == 0);

    logic n_sq_retire_stall;
    assign n_sq_retire_stall = ~i_sq_retire_stall;

    // Find a retirable store to launch into the LSU
    logic [OPTN_SQ_DEPTH-1:0] sq_retire_picked;
    procyon_priority_picker #(OPTN_SQ_DEPTH) sq_retire_picked_priority_picker (.i_in(sq_entry_retirable), .o_pick(sq_retire_picked));
    assign sq_retire_select = {(OPTN_SQ_DEPTH){n_sq_retire_stall}} & sq_retire_picked;

    // Convert one-hot retire_select vector into binary SQ entry #
    logic [SQ_IDX_WIDTH-1:0] sq_retire_entry;
    procyon_onehot2binary #(OPTN_SQ_DEPTH) sq_retire_entry_onehot2binary (.i_onehot(sq_retire_select), .o_binary(sq_retire_entry));

    // Retire stores to D$ or to the MHQ if it misses in the cache
    // The retiring store address and type and sq_retire_en signals is also sent to the LQ for possible load bypass violation detection
    logic sq_retire_en;
    assign sq_retire_en = ~i_flush & (sq_retire_select != 0);
    procyon_srff #(1) o_sq_retire_en_srff (.clk(clk), .n_rst(n_rst), .i_en(n_sq_retire_stall), .i_set(sq_retire_en), .i_reset(1'b0), .o_q(o_sq_retire_en));

    procyon_ff #(OPTN_SQ_DEPTH) o_sq_retire_select_ff (.clk(clk), .i_en(n_sq_retire_stall), .i_d(sq_retire_select), .o_q(o_sq_retire_select));
    procyon_ff #(`PCYN_OP_WIDTH) o_sq_retire_op_ff (.clk(clk), .i_en(n_sq_retire_stall), .i_d(sq_retire_op[sq_retire_entry]), .o_q(o_sq_retire_op));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_sq_retire_tag_ff (.clk(clk), .i_en(n_sq_retire_stall), .i_d(sq_retire_tag[sq_retire_entry]), .o_q(o_sq_retire_tag));
    procyon_ff #(OPTN_DATA_WIDTH) o_sq_retire_data_ff (.clk(clk), .i_en(n_sq_retire_stall), .i_d(sq_retire_data[sq_retire_entry]), .o_q(o_sq_retire_data));
    procyon_ff #(OPTN_ADDR_WIDTH) o_sq_retire_addr_ff (.clk(clk), .i_en(n_sq_retire_stall), .i_d(sq_retire_addr[sq_retire_entry]), .o_q(o_sq_retire_addr));

    // Send ack back to ROB when launching the retired store
    logic rob_retire_ack;
    assign rob_retire_ack = (sq_rob_retire_ack != 0);
    procyon_srff #(1) o_rob_retire_ack_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(rob_retire_ack), .i_reset(1'b0), .o_q(o_rob_retire_ack));

endmodule
