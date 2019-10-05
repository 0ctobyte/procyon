/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

`include "procyon_constants.svh"

module procyon_rob_entry #(
    parameter OPTN_DATA_WIDTH       = 32,
    parameter OPTN_ADDR_WIDTH       = 32,
    parameter OPTN_CDB_DEPTH        = 2,
    parameter OPTN_ROB_IDX_WIDTH    = 5,
    parameter OPTN_REGMAP_IDX_WIDTH = 5
)(
    input  logic                              clk,
    input  logic                              n_rst,

    input  logic                              i_redirect,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]     i_rob_tag,

    output logic                              o_retirable,
    output logic                              o_lsu_pending,
    output logic                              o_rob_entry_redirect,
    output logic [OPTN_ADDR_WIDTH-1:0]        o_rob_entry_addr,
    output logic [OPTN_DATA_WIDTH-1:0]        o_rob_entry_data,
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0]  o_rob_entry_rdest,
    output logic [`PCYN_ROB_OP_WIDTH-1:0]     o_rob_entry_op,
    output logic [OPTN_ADDR_WIDTH-1:0]        o_rob_entry_pc,

    // Common Data Bus networks
    input  logic                              i_cdb_en       [0:OPTN_CDB_DEPTH-1],
    input  logic                              i_cdb_redirect [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_DATA_WIDTH-1:0]        i_cdb_data     [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_ADDR_WIDTH-1:0]        i_cdb_addr     [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]     i_cdb_tag      [0:OPTN_CDB_DEPTH-1],

    // Enqueue to this entry
    input  logic                              i_dispatch_en,
    input  logic [`PCYN_ROB_OP_WIDTH-1:0]     i_dispatch_op,
    input  logic [OPTN_ADDR_WIDTH-1:0]        i_dispatch_pc,
    input  logic [OPTN_REGMAP_IDX_WIDTH-1:0]  i_dispatch_rdest,

    // Retire this entry. For loads/stores, handshake is required between LSU in case of mis-speculated loads and to
    // keep the LQ and SQ in sync with the ROB
    input  logic                              i_retire_en,
    input  logic                              i_lsu_retire_lq_ack,
    input  logic                              i_lsu_retire_sq_ack,
    input  logic                              i_lsu_retire_misspeculated
);
    localparam ROB_STATE_WIDTH       = 2;
    localparam ROB_STATE_INVALID     = 2'b00;
    localparam ROB_STATE_PENDING     = 2'b01;
    localparam ROB_STATE_LSU_PENDING = 2'b10;
    localparam ROB_STATE_RETIRABLE   = 2'b11;

    // ROB entry consists of the following:
    // redirect:    Asserted by branches or instructions that cause exceptions
    // lsu_op:      Indicates if the op is a load/store op
    // op:          What operation is the instruction doing?
    // pc:          Address of the instruction (to rollback on exception
    // rdest:       The destination register
    // addr:        Destination address for branch
    // data:        The data for the destination register
    // state:       State of the ROB entry
    logic rob_entry_redirect_r;
    logic rob_entry_lsu_op_r;
    logic [`PCYN_ROB_OP_WIDTH-1:0] rob_entry_op_r;
    logic [OPTN_ADDR_WIDTH-1:0] rob_entry_pc_r;
    logic [OPTN_REGMAP_IDX_WIDTH-1:0] rob_entry_rdest_r ;
    logic [OPTN_ADDR_WIDTH-1:0] rob_entry_addr_r;
    logic [OPTN_DATA_WIDTH-1:0] rob_entry_data_r;
    logic [ROB_STATE_WIDTH-1:0] rob_entry_state_r;

    // An ROB entry holding a LD/ST op can only move on to the retired state if it's in the lsu_pending state and the
    // LSU sends back an ack
    logic rob_entry_lsu_pending;
    logic lsu_retired_ack;

    assign rob_entry_lsu_pending = (rob_entry_state_r == ROB_STATE_LSU_PENDING);
    assign lsu_retired_ack = rob_entry_lsu_pending & ((rob_entry_op_r == `PCYN_ROB_OP_LD & i_lsu_retire_lq_ack) | (rob_entry_op_r == `PCYN_ROB_OP_ST & i_lsu_retire_sq_ack));

    // Check CDB inputs for matching tags and determine which entry can be marked as retirable
    // Also mux in address, data and redirect information from CDB
    logic rob_entry_redirect_mux;
    logic [OPTN_ADDR_WIDTH-1:0] rob_entry_addr_mux;
    logic [OPTN_DATA_WIDTH-1:0] rob_entry_data_mux;
    logic rob_entry_retirable;

    always_comb begin
        rob_entry_redirect_mux = lsu_retired_ack ? i_lsu_retire_misspeculated : rob_entry_redirect_r;
        rob_entry_addr_mux = rob_entry_addr_r;
        rob_entry_data_mux = rob_entry_data_r;
        rob_entry_retirable = 1'b0;

        for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
            logic cdb_tag_match;
            cdb_tag_match = i_cdb_en[cdb_idx] & (i_rob_tag == i_cdb_tag[cdb_idx]);

            rob_entry_redirect_mux = cdb_tag_match ? i_cdb_redirect[cdb_idx] : rob_entry_redirect_mux;
            rob_entry_addr_mux = cdb_tag_match ? i_cdb_addr[cdb_idx] : rob_entry_addr_mux;
            rob_entry_data_mux = cdb_tag_match ? i_cdb_data[cdb_idx] : rob_entry_data_mux;
            rob_entry_retirable = cdb_tag_match | rob_entry_retirable;
        end

        // Clear the redirect bit if an instruction is being enqueued at the entry
        rob_entry_redirect_mux = ~i_dispatch_en & rob_entry_redirect_mux;
    end

    procyon_ff #(1) rob_entry_redirect_r_ff (.clk(clk), .i_en(1'b1), .i_d(rob_entry_redirect_mux), .o_q(rob_entry_redirect_r));
    procyon_ff #(OPTN_ADDR_WIDTH) rob_entry_addr_r_ff (.clk(clk), .i_en(1'b1), .i_d(rob_entry_addr_mux), .o_q(rob_entry_addr_r));
    procyon_ff #(OPTN_DATA_WIDTH) rob_entry_data_r_ff (.clk(clk), .i_en(1'b1), .i_d(rob_entry_data_mux), .o_q(rob_entry_data_r));

    // These registers only get updated if the entry is getting enqueued
    logic rob_entry_lsu_op;
    assign rob_entry_lsu_op = (i_dispatch_op == `PCYN_ROB_OP_LD | i_dispatch_op == `PCYN_ROB_OP_ST);
    procyon_ff #(1) rob_entry_lsu_op_r_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(rob_entry_lsu_op), .o_q(rob_entry_lsu_op_r));

    procyon_ff #(`PCYN_ROB_OP_WIDTH) rob_entry_op_r_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(i_dispatch_op), .o_q(rob_entry_op_r));
    procyon_ff #(OPTN_ADDR_WIDTH) rob_entry_pc_r_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(i_dispatch_pc), .o_q(rob_entry_pc_r));
    procyon_ff #(OPTN_REGMAP_IDX_WIDTH) rob_entry_rdest_r_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(i_dispatch_rdest), .o_q(rob_entry_rdest_r));

    // ROB entry next state logic
    // Each ROB entry progresses through up to 4 states (at least 3 of them, LSU ops go through an extra state)
    // ROB_STATE_PENDING: From INVALID to PENDING when a ROB entry is enqueued
    // ROB_STATE_LSU_PENDING: LSU ops are put in the LSU_PENDING state waiting for an ack from the LQ or SQ
    // This is needed to allow the LQ to signal back whether the load has been misspeculated and for the SQ to acknowledge that store has been written out to memeory
    // In both cases the LQ and SQ dequeue the op
    // ROB_STATE_RETIRABLE: This indicates that the op has completed execution and can be retired when it reaches the head of the ROB
    logic [ROB_STATE_WIDTH-1:0] rob_entry_state_next;

    always_comb begin
        logic [ROB_STATE_WIDTH-1:0] rob_entry_state_lsu_pending_mux;
        rob_entry_state_lsu_pending_mux = rob_entry_lsu_op_r ? ROB_STATE_LSU_PENDING : ROB_STATE_RETIRABLE;

        case (rob_entry_state_r)
            ROB_STATE_INVALID:     rob_entry_state_next = i_dispatch_en ? ROB_STATE_PENDING : ROB_STATE_INVALID;
            ROB_STATE_PENDING:     rob_entry_state_next = rob_entry_retirable ? rob_entry_state_lsu_pending_mux : ROB_STATE_PENDING;
            ROB_STATE_LSU_PENDING: rob_entry_state_next = lsu_retired_ack ? ROB_STATE_RETIRABLE : ROB_STATE_LSU_PENDING;
            ROB_STATE_RETIRABLE:   rob_entry_state_next = i_retire_en ? ROB_STATE_INVALID : ROB_STATE_RETIRABLE;
            default:               rob_entry_state_next = ROB_STATE_INVALID;
        endcase

        rob_entry_state_next = i_redirect ? ROB_STATE_INVALID : rob_entry_state_next;
    end

    procyon_srff #(ROB_STATE_WIDTH) rob_entry_state_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(rob_entry_state_next), .i_reset(ROB_STATE_INVALID), .o_q(rob_entry_state_r));

    // Signal to indicate if this entry is retirable
    assign o_retirable = (rob_entry_state_r == ROB_STATE_RETIRABLE);

    // Signal to indicate if this entry is waiting on an ack from the LSU
    assign o_lsu_pending = rob_entry_lsu_pending;

    // Output entry data
    assign o_rob_entry_redirect = rob_entry_redirect_r;
    assign o_rob_entry_addr = rob_entry_addr_r;
    assign o_rob_entry_data = rob_entry_data_r;
    assign o_rob_entry_rdest = rob_entry_rdest_r;
    assign o_rob_entry_op = rob_entry_op_r;
    assign o_rob_entry_pc = rob_entry_pc_r;

endmodule
