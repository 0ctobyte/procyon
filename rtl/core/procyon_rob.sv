/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Re-Order Buffer
// Every cycle a new entry may be allocated at the tail of the buffer
// Every cycle a ready entry from the head of the FIFO is committed to the register file
// This enforces instructions to complete in program order

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
import procyon_core_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_rob #(
    parameter OPTN_DATA_WIDTH       = 32,
    parameter OPTN_ADDR_WIDTH       = 32,
    parameter OPTN_CDB_DEPTH        = 2,
    parameter OPTN_ROB_DEPTH        = 32,
    parameter OPTN_RAT_IDX_WIDTH    = 5
)(
    input  logic                                 clk,
    input  logic                                 n_rst,

    output logic                                 o_rob_stall,

    // The redirect signal and addr/pc are used by the Fetch unit to jump to the redirect address
    // Used for branches, exception etc.
    output logic                                 o_redirect,
    output logic [OPTN_ADDR_WIDTH-1:0]           o_redirect_addr,

    // Common Data Bus networks
    input  logic                                 i_cdb_en [0:OPTN_CDB_DEPTH-1],
    input  logic                                 i_cdb_redirect [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_DATA_WIDTH-1:0]           i_cdb_data [0:OPTN_CDB_DEPTH-1],
    input  logic [`PCYN_C2I(OPTN_ROB_DEPTH)-1:0] i_cdb_tag [0:OPTN_CDB_DEPTH-1],

    // Dispatcher interface to reserve an entry for enqueuing in the next cycle. The tag is forwarded to Register Alias Table
    // to rename the destination register for this new instruction
    input  logic                                 i_rob_reserve_en,
    output logic [`PCYN_C2I(OPTN_ROB_DEPTH)-1:0] o_rob_reserve_tag,

    // Lookup data/tags for source operands of newly enqueued instructions
    input  logic [`PCYN_C2I(OPTN_ROB_DEPTH)-1:0] i_rob_lookup_tag [0:1],
    output logic                                 o_rob_lookup_rdy [0:1],
    output logic [OPTN_DATA_WIDTH-1:0]           o_rob_lookup_data [0:1],

    // Dispatcher <-> ROB interface to enqueue a new instruction
    input  pcyn_op_is_t                          i_rob_dispatch_op_is,
    input  logic [OPTN_ADDR_WIDTH-1:0]           i_rob_dispatch_pc,
    input  logic [OPTN_RAT_IDX_WIDTH-1:0]        i_rob_dispatch_rdst,
    input  logic [OPTN_DATA_WIDTH-1:0]           i_rob_dispatch_rdst_data,

    // Interface to register alias table to update destination register for retired instruction
    output logic [OPTN_DATA_WIDTH-1:0]           o_rat_retire_data,
    output logic [OPTN_RAT_IDX_WIDTH-1:0]        o_rat_retire_rdst,
    output logic [`PCYN_C2I(OPTN_ROB_DEPTH)-1:0] o_rat_retire_tag,
    output logic                                 o_rat_retire_en,

    // Interface to LSU to retire loads/stores
    input  logic                                 i_lsu_retire_lq_ack,
    input  logic                                 i_lsu_retire_sq_ack,
    input  logic                                 i_lsu_retire_misspeculated,
    output logic                                 o_lsu_retire_lq_en,
    output logic                                 o_lsu_retire_sq_en,
    output logic [`PCYN_C2I(OPTN_ROB_DEPTH)-1:0] o_lsu_retire_tag
);

    localparam ROB_IDX_WIDTH = `PCYN_C2I(OPTN_ROB_DEPTH);

    logic [ROB_IDX_WIDTH-1:0] rob_queue_head;
    logic [ROB_IDX_WIDTH-1:0] rob_queue_tail;
    logic rob_queue_full;
/* verilator lint_off UNUSED */
    logic rob_queue_empty;
/* verilator lint_on  UNUSED */

    logic [OPTN_ROB_DEPTH-1:0] rob_entry_retirable;
    logic [OPTN_ROB_DEPTH-1:0] rob_entry_lsu_pending;
    logic [OPTN_ROB_DEPTH-1:0] rob_entry_redirect;
    logic [OPTN_DATA_WIDTH-1:0] rob_entry_data [OPTN_ROB_DEPTH-1:0];
    logic [OPTN_RAT_IDX_WIDTH-1:0] rob_entry_rdst [OPTN_ROB_DEPTH-1:0];
    pcyn_op_is_t rob_entry_op_is [OPTN_ROB_DEPTH-1:0];
    logic [OPTN_ADDR_WIDTH-1:0] rob_entry_pc [OPTN_ROB_DEPTH-1:0];
    logic [OPTN_ROB_DEPTH-1:0] rob_dispatch_select_r;
    logic [OPTN_ROB_DEPTH-1:0] rob_retire_select;
    logic [OPTN_ROB_DEPTH-1:0] lsu_retire_lq_ack_select;
    logic [OPTN_ROB_DEPTH-1:0] lsu_retire_sq_ack_select;

    // Clear the entries in the same cycle the redirect is detected. The redirect is sent to the rest of the chip
    // in the next cycle through the redirect_r register.
    logic redirect;
    assign redirect = rob_entry_retirable[rob_queue_head] & rob_entry_redirect[rob_queue_head];

    genvar inst;
    generate
    for (inst = 0; inst < OPTN_ROB_DEPTH; inst++) begin : GEN_ROB_ENTRY_INST
        procyon_rob_entry #(
            .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
            .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
            .OPTN_CDB_DEPTH(OPTN_CDB_DEPTH),
            .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH),
            .OPTN_RAT_IDX_WIDTH(OPTN_RAT_IDX_WIDTH)
        ) procyon_rob_entry_inst (
            .clk(clk),
            .n_rst(n_rst),
            .i_redirect(redirect),
            .i_rob_tag(ROB_IDX_WIDTH'(inst)),
            .o_retirable(rob_entry_retirable[inst]),
            .o_lsu_pending(rob_entry_lsu_pending[inst]),
            .o_rob_entry_redirect(rob_entry_redirect[inst]),
            .o_rob_entry_data(rob_entry_data[inst]),
            .o_rob_entry_rdst(rob_entry_rdst[inst]),
            .o_rob_entry_op_is(rob_entry_op_is[inst]),
            .o_rob_entry_pc(rob_entry_pc[inst]),
            .i_cdb_en(i_cdb_en),
            .i_cdb_redirect(i_cdb_redirect),
            .i_cdb_data(i_cdb_data),
            .i_cdb_tag(i_cdb_tag),
            .i_dispatch_en(rob_dispatch_select_r[inst]),
            .i_dispatch_op_is(i_rob_dispatch_op_is),
            .i_dispatch_pc(i_rob_dispatch_pc),
            .i_dispatch_rdst(i_rob_dispatch_rdst),
            .i_dispatch_rdst_data(i_rob_dispatch_rdst_data),
            .i_retire_en(rob_retire_select[inst]),
            .i_lsu_retire_lq_ack(lsu_retire_lq_ack_select[inst]),
            .i_lsu_retire_sq_ack(lsu_retire_sq_ack_select[inst]),
            .i_lsu_retire_misspeculated(i_lsu_retire_misspeculated)
        );
    end
    endgenerate

    // Check if a reserve and retire event are occurring in this cycle. rob_queue_head, rob_queue_tail and the rob_entry_counter_r
    // all depend on these signals.
    logic rob_reserve_en;
    logic rob_retire_en;

    assign rob_reserve_en = i_rob_reserve_en;
    assign rob_retire_en = rob_entry_retirable[rob_queue_head];

    // Increment the tail pointer to reserve an entry when the Dispatcher is in the renaming cycle and the ROB is not full.
    // On the next cycle the entry will be filled. Reset if redirect asserted. Increment the head pointer if the instruction
    // is retirable  and the ROB is not empty (of course this should never be the case). Reset if redirect asserted
    procyon_queue_ctrl #(
        .OPTN_QUEUE_DEPTH(OPTN_ROB_DEPTH)
    ) rob_queue_ctrl (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(redirect_r),
        .i_incr_head(rob_retire_en),
        .i_incr_tail(rob_reserve_en),
        .o_queue_head(rob_queue_head),
        .o_queue_tail(rob_queue_tail),
        .o_queue_full(rob_queue_full),
        .o_queue_empty(rob_queue_empty)
    );

    // Generate a one-hot vector reserving an ROB entry for the next cycle when the dispatcher will enqueue into the entry
    logic [OPTN_ROB_DEPTH-1:0] rob_reserve_select;

    always_comb begin
        rob_reserve_select = '0;
        rob_reserve_select[rob_queue_tail] = rob_reserve_en;
    end

    procyon_ff #(OPTN_ROB_DEPTH) rob_dispatch_select_r_ff (.clk(clk), .i_en(1'b1), .i_d(rob_reserve_select), .o_q(rob_dispatch_select_r));

    // Only allow the head ROB entry to retire. This is basically a "is_head" signal passed to each entry.
    always_comb begin
        rob_retire_select = '0;
        rob_retire_select[rob_queue_head] = 1'b1;

        lsu_retire_lq_ack_select = '0;
        lsu_retire_lq_ack_select[rob_queue_head] = i_lsu_retire_lq_ack;

        lsu_retire_sq_ack_select = '0;
        lsu_retire_sq_ack_select[rob_queue_head] = i_lsu_retire_sq_ack;
    end

    // If the instruction to be retired generated a branch/mispredict then assert the redirect signal and address
    logic redirect_r;
    procyon_srff #(1) redirect_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(redirect), .i_reset(1'b0), .o_q(redirect_r));

    assign o_redirect = redirect_r;

    logic [OPTN_ADDR_WIDTH-1:0] redirect_addr_mux;
    assign redirect_addr_mux = rob_entry_pc[rob_queue_head];
    procyon_ff #(OPTN_ADDR_WIDTH) o_redirect_addr_ff (.clk(clk), .i_en(1'b1), .i_d(redirect_addr_mux), .o_q(o_redirect_addr));

    // Send the next free ROB entry number to the Register Alias Table so it can use it to rename the destination register for a new instruction
    assign o_rob_reserve_tag = rob_queue_tail;

    // Output stall if the ROB is full
    assign o_rob_stall = rob_queue_full;

    // Lookup source tags for the decoding stage. Make sure to bypass from the CDB if necessary
    logic rob_lookup_rdy [0:1];
    logic [OPTN_DATA_WIDTH-1:0] rob_lookup_data_mux [0:1];

    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            logic [ROB_IDX_WIDTH-1:0] rob_tag;
            rob_tag = i_rob_lookup_tag[src_idx];

            rob_lookup_rdy[src_idx] = rob_entry_retirable[rob_tag] | rob_entry_lsu_pending[rob_tag];
            rob_lookup_data_mux[src_idx] = rob_entry_data[rob_tag];

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                logic cdb_lookup_bypass;
                cdb_lookup_bypass = i_cdb_en[cdb_idx] & (i_cdb_tag[cdb_idx] == rob_tag);

                rob_lookup_rdy[src_idx] = cdb_lookup_bypass | rob_lookup_rdy[src_idx];
                rob_lookup_data_mux[src_idx] = cdb_lookup_bypass ? i_cdb_data[cdb_idx] : rob_lookup_data_mux[src_idx];
            end
        end
    end

    assign o_rob_lookup_rdy = rob_lookup_rdy;
    assign o_rob_lookup_data = rob_lookup_data_mux;

    // Let the LSU know that the instruction at the head of the ROB is ready to be retired and is waiting for an ack from the LSU
    procyon_ff #(ROB_IDX_WIDTH) o_lsu_retire_tag_ff (.clk(clk), .i_en(1'b1), .i_d(rob_queue_head), .o_q(o_lsu_retire_tag));

    logic n_redirect;
    assign n_redirect = ~redirect_r;

    logic lsu_retire_lq_en;
    assign lsu_retire_lq_en = n_redirect & rob_entry_lsu_pending[rob_queue_head] & rob_entry_op_is[rob_queue_head][PCYN_OP_IS_LD_IDX] & ~i_lsu_retire_lq_ack;
    procyon_ff #(1) o_lsu_retire_lq_en_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_retire_lq_en), .o_q(o_lsu_retire_lq_en));

    logic lsu_retire_sq_en;
    assign lsu_retire_sq_en = n_redirect & rob_entry_lsu_pending[rob_queue_head] & rob_entry_op_is[rob_queue_head][PCYN_OP_IS_ST_IDX] & ~i_lsu_retire_sq_ack;
    procyon_ff #(1) o_lsu_retire_sq_en_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_retire_sq_en), .o_q(o_lsu_retire_sq_en));

    // Let the Regmap know that this instruction is retiring in order to update the destination register alias mapping
    procyon_srff #(1) o_rat_retire_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(rob_retire_en), .i_reset(1'b0), .o_q(o_rat_retire_en));
    procyon_ff #(OPTN_DATA_WIDTH) o_rat_retire_data_ff (.clk(clk), .i_en(1'b1), .i_d(rob_entry_data[rob_queue_head]), .o_q(o_rat_retire_data));
    procyon_ff #(OPTN_RAT_IDX_WIDTH) o_rat_retire_rdst_ff (.clk(clk), .i_en(1'b1), .i_d(rob_entry_rdst[rob_queue_head]), .o_q(o_rat_retire_rdst));
    procyon_ff #(ROB_IDX_WIDTH) o_rat_retire_tag_ff (.clk(clk), .i_en(1'b1), .i_d(rob_queue_head), .o_q(o_rat_retire_tag));

endmodule
