/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Load Queue
// Every cycle a new load op may be allocated in the load queue when issued from the reservation station
// Every cycle a load may be deallocated from the load queue when retired from the ROB
// Every cycle a stalled load can be replayed if the cacheline it was waiting for is returned from memory
// The purpose of the load queue is to keep track of load ops until they are retired and to detect
// mis-speculated loads whenever a store op has been retired

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
import procyon_core_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_lsu_lq #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_LQ_DEPTH      = 8,
    parameter OPTN_ROB_IDX_WIDTH = 5,
    parameter OPTN_MHQ_IDX_WIDTH = 2
)(
    input  logic                          clk,
    input  logic                          n_rst,

    input  logic                          i_flush,
    input  logic                          i_sq_nonspeculative_pending,
    output logic                          o_full,

    // Signals from LSU_ID to allocate new load op
    input  logic                          i_alloc_en,
    input  pcyn_op_t                      i_alloc_op,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_alloc_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]    i_alloc_addr,
    output logic [OPTN_LQ_DEPTH-1:0]      o_alloc_lq_select,

    // Signals to LSU_EX for replaying loads
    input  logic                          i_replay_stall,
    output logic                          o_replay_en,
    output logic [OPTN_LQ_DEPTH-1:0]      o_replay_select,
    output pcyn_op_t                      o_replay_op,
    output logic [OPTN_ROB_IDX_WIDTH-1:0] o_replay_tag,
    output logic [OPTN_ADDR_WIDTH-1:0]    o_replay_addr,

    // Signals from LSU_EX and MHQ_LU to update a load when it needs to be retried later or replayed ASAP
    input  logic                          i_update_en,
    input  logic [OPTN_LQ_DEPTH-1:0]      i_update_select,
    input  logic                          i_update_retry,
    input  logic                          i_update_replay,
    input  logic [OPTN_MHQ_IDX_WIDTH-1:0] i_update_mhq_tag,
    input  logic                          i_update_mhq_retry,
    input  logic                          i_update_mhq_replay,

    // MHQ fill broadcast
    input  logic                          i_mhq_fill_en,
    input  logic [OPTN_MHQ_IDX_WIDTH-1:0] i_mhq_fill_tag,

    // SQ will send address of retiring store for mis-speculation detection
    input  logic                          i_sq_retire_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]    i_sq_retire_addr,
    input  pcyn_op_t                      i_sq_retire_op,

    // ROB signal that a load has been retired
    input  logic                          i_rob_retire_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_rob_retire_tag,
    output logic                          o_rob_retire_ack,
    output logic                          o_rob_retire_misspeculated
);

    localparam LQ_IDX_WIDTH = `PCYN_C2I(OPTN_LQ_DEPTH);

    // Override the rob_retire_en signal if there are pending nonspeculative stores (i.e. stores that have not been
    // written to the cache yet)
    logic rob_retire_en;
    assign rob_retire_en = i_rob_retire_en & ~i_sq_nonspeculative_pending;

    // Calculate ending address for the retiring store
    logic [OPTN_ADDR_WIDTH-1:0] sq_retire_addr_end;

    always_comb begin
        unique case (i_sq_retire_op)
            PCYN_OP_SB: sq_retire_addr_end = i_sq_retire_addr + OPTN_ADDR_WIDTH'(1);
            PCYN_OP_SH: sq_retire_addr_end = i_sq_retire_addr + OPTN_ADDR_WIDTH'(2);
            PCYN_OP_SW: sq_retire_addr_end = i_sq_retire_addr + OPTN_ADDR_WIDTH'(4);
            default:    sq_retire_addr_end = i_sq_retire_addr + OPTN_ADDR_WIDTH'(4);
        endcase
    end

    logic [OPTN_LQ_DEPTH-1:0] lq_entry_empty;
    logic [OPTN_LQ_DEPTH-1:0] lq_entry_replayable;
    logic [OPTN_LQ_DEPTH-1:0] lq_allocate_select;
    logic [OPTN_LQ_DEPTH-1:0] lq_replay_select;
    logic [OPTN_LQ_DEPTH-1:0] lq_update_select;
    pcyn_op_t lq_replay_op [0:OPTN_LQ_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0] lq_replay_addr [0:OPTN_LQ_DEPTH-1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] lq_replay_tag [0:OPTN_LQ_DEPTH-1];
    logic [OPTN_LQ_DEPTH-1:0] lq_rob_retire_ack;
    logic [OPTN_LQ_DEPTH-1:0] lq_rob_retire_misspeculated;

    genvar inst;
    generate
    for (inst = 0; inst < OPTN_LQ_DEPTH; inst++) begin : GEN_LSU_LQ_ENTRY_INST
        procyon_lsu_lq_entry #(
            .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
            .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
            .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH),
            .OPTN_MHQ_IDX_WIDTH(OPTN_MHQ_IDX_WIDTH)
        ) procyon_lsu_lq_entry_inst (
            .clk(clk),
            .n_rst(n_rst),
            .i_flush(i_flush),
            .o_empty(lq_entry_empty[inst]),
            .o_replayable(lq_entry_replayable[inst]),
            .i_alloc_en(lq_allocate_select[inst]),
            .i_alloc_op(i_alloc_op),
            .i_alloc_tag(i_alloc_tag),
            .i_alloc_addr(i_alloc_addr),
            .i_replay_en(lq_replay_select[inst]),
            .o_replay_op(lq_replay_op[inst]),
            .o_replay_tag(lq_replay_tag[inst]),
            .o_replay_addr(lq_replay_addr[inst]),
            .i_update_en(lq_update_select[inst]),
            .i_update_retry(i_update_retry),
            .i_update_replay(i_update_replay),
            .i_update_mhq_tag(i_update_mhq_tag),
            .i_update_mhq_retry(i_update_mhq_retry),
            .i_update_mhq_replay(i_update_mhq_replay),
            .i_mhq_fill_en(i_mhq_fill_en),
            .i_mhq_fill_tag(i_mhq_fill_tag),
            .i_sq_retire_en(i_sq_retire_en),
            .i_sq_retire_addr(i_sq_retire_addr),
            .i_sq_retire_addr_end(sq_retire_addr_end),
            .i_rob_retire_en(rob_retire_en),
            .i_rob_retire_tag(i_rob_retire_tag),
            .o_rob_retire_ack(lq_rob_retire_ack[inst]),
            .o_rob_retire_misspeculated(lq_rob_retire_misspeculated[inst])
        );
    end
    endgenerate

    // One hot vector indicating which LQ entry needs to be updated
    assign lq_update_select = {(OPTN_LQ_DEPTH){i_update_en}} & i_update_select;

    // Find an empty LQ entry that can be used to allocate a new load
    logic [OPTN_LQ_DEPTH-1:0] lq_allocate_picked;
    procyon_priority_picker #(OPTN_LQ_DEPTH) lq_allocate_picked_priority_picker (.i_in(lq_entry_empty), .o_pick(lq_allocate_picked));
    assign lq_allocate_select = {(OPTN_LQ_DEPTH){i_alloc_en}} & lq_allocate_picked;

    // Output LQ select vector on allocate request
    procyon_ff #(OPTN_LQ_DEPTH) o_alloc_lq_select_ff (.clk(clk), .i_en(1'b1), .i_d(lq_allocate_select), .o_q(o_alloc_lq_select));

    // Ouput full-on-next-cycle signal (i.e. The last entry will be allocated on this cycle means it will be full on the next cycle)
    assign o_full = ((lq_entry_empty & ~lq_allocate_select) == 0);

    logic n_replay_stall;
    assign n_replay_stall = ~i_replay_stall;

    // Find a load in the LQ that can be replayed
    logic [OPTN_LQ_DEPTH-1:0] lq_replay_picked;
    procyon_priority_picker #(OPTN_LQ_DEPTH) lq_replay_picked_priority_picker (.i_in(lq_entry_replayable), .o_pick(lq_replay_picked));
    assign lq_replay_select = {(OPTN_LQ_DEPTH){n_replay_stall}} & lq_replay_picked;

    // Output replaying load to LSU
    logic lq_replay_en_srff;
    assign lq_replay_en_srff = n_replay_stall | i_flush;

    logic lq_replay_en;
    assign lq_replay_en = ~i_flush & (lq_replay_select != 0);
    procyon_srff #(1) o_replay_en_srff (.clk(clk), .n_rst(n_rst), .i_en(lq_replay_en_srff), .i_set(lq_replay_en), .i_reset(1'b0), .o_q(o_replay_en));

    // Convert one-hot replay_select vector into binary LQ entry #
    logic [LQ_IDX_WIDTH-1:0] lq_replay_entry;
    procyon_onehot2binary #(OPTN_LQ_DEPTH) lq_replay_entry_onehot2binary (.i_onehot(lq_replay_select), .o_binary(lq_replay_entry));

    procyon_ff #(OPTN_LQ_DEPTH) o_replay_select_ff (.clk(clk), .i_en(n_replay_stall), .i_d(lq_replay_select), .o_q(o_replay_select));
    procyon_ff #(PCYN_OP_WIDTH) o_replay_op_ff (.clk(clk), .i_en(n_replay_stall), .i_d(lq_replay_op[lq_replay_entry]), .o_q(o_replay_op));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_replay_tag_ff (.clk(clk), .i_en(n_replay_stall), .i_d(lq_replay_tag[lq_replay_entry]), .o_q(o_replay_tag));
    procyon_ff #(OPTN_ADDR_WIDTH) o_replay_addr_ff (.clk(clk), .i_en(n_replay_stall), .i_d(lq_replay_addr[lq_replay_entry]), .o_q(o_replay_addr));

    // Let ROB know that retired load was mis-speculated
    // Send ack back to ROB with mis-speculated signal when ROB indicates load to be retired
    logic rob_retire_ack;
    assign rob_retire_ack = (lq_rob_retire_ack != 0);
    procyon_srff #(1) o_rob_retire_ack_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(rob_retire_ack), .i_reset(1'b0), .o_q(o_rob_retire_ack));

    // Convert one-hot retire_ack vector into binary LQ entry #
    logic [LQ_IDX_WIDTH-1:0] lq_retire_entry;
    procyon_onehot2binary #(OPTN_LQ_DEPTH) lq_retire_entry_onehot2binary (.i_onehot(lq_rob_retire_ack), .o_binary(lq_retire_entry));
    procyon_ff #(1) o_rob_retire_misspeculated_ff (.clk(clk), .i_en(1'b1), .i_d(lq_rob_retire_misspeculated[lq_retire_entry]), .o_q(o_rob_retire_misspeculated));

endmodule
