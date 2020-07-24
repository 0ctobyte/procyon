/*
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Re-Order Buffer
// Every cycle a new entry may be allocated at the tail of the buffer
// Every cycle a ready entry from the head of the FIFO is committed to the register file
// This enforces instructions to complete in program order

`include "procyon_constants.svh"

module procyon_rob #(
    parameter OPTN_DATA_WIDTH       = 32,
    parameter OPTN_ADDR_WIDTH       = 32,
    parameter OPTN_CDB_DEPTH        = 2,
    parameter OPTN_ROB_DEPTH        = 32,
    parameter OPTN_REGMAP_IDX_WIDTH = 5,

    parameter ROB_IDX_WIDTH         = $clog2(OPTN_ROB_DEPTH)
)(
    input  logic                              clk,
    input  logic                              n_rst,

    input  logic                              i_rs_stall,
    output logic                              o_rob_stall,

    // The redirect signal and addr/pc are used by the Fetch unit to jump to the redirect address
    // Used for branches, exception etc.
    output logic                              o_redirect,
    output logic [OPTN_ADDR_WIDTH-1:0]        o_redirect_addr,

    // Common Data Bus networks
    input  logic                              i_cdb_en              [0:OPTN_CDB_DEPTH-1],
    input  logic                              i_cdb_redirect        [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_DATA_WIDTH-1:0]        i_cdb_data            [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_ADDR_WIDTH-1:0]        i_cdb_addr            [0:OPTN_CDB_DEPTH-1],
    input  logic [ROB_IDX_WIDTH-1:0]          i_cdb_tag             [0:OPTN_CDB_DEPTH-1],

    // Dispatcher <-> ROB interface to enqueue a new instruction
    input  logic                              i_rob_enq_en,
    input  logic [`PCYN_ROB_OP_WIDTH-1:0]     i_rob_enq_op,
    input  logic [OPTN_ADDR_WIDTH-1:0]        i_rob_enq_pc,
    input  logic [OPTN_REGMAP_IDX_WIDTH-1:0]  i_rob_enq_rdest,

    // Looup data/tags for source operands of newly enqueued instructions
    input  logic [OPTN_DATA_WIDTH-1:0]        i_rob_lookup_data     [0:1],
    input  logic [ROB_IDX_WIDTH-1:0]          i_rob_lookup_tag      [0:1],
    input  logic                              i_rob_lookup_rdy      [0:1],
    input  logic                              i_rob_lookup_rdy_ovrd [0:1],
    output logic [OPTN_DATA_WIDTH-1:0]        o_rs_src_data         [0:1],
    output logic [ROB_IDX_WIDTH-1:0]          o_rs_src_tag          [0:1],
    output logic                              o_rs_src_rdy          [0:1],

    // Interface to register map to update tag information of the destination register of the newly enqueued instruction
    output logic [ROB_IDX_WIDTH-1:0]          o_regmap_rename_tag,
    input  logic                              i_regmap_rename_en,

    // Interface to register map to update destination register for retired instruction
    output logic [OPTN_DATA_WIDTH-1:0]        o_regmap_retire_data,
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0]  o_regmap_retire_rdest,
    output logic [ROB_IDX_WIDTH-1:0]          o_regmap_retire_tag,
    output logic                              o_regmap_retire_en,

    // Interface to LSU to retire loads/stores
    input  logic                              i_lsu_retire_lq_ack,
    input  logic                              i_lsu_retire_sq_ack,
    input  logic                              i_lsu_retire_misspeculated,
    output logic                              o_lsu_retire_lq_en,
    output logic                              o_lsu_retire_sq_en,
    output logic [ROB_IDX_WIDTH-1:0]          o_lsu_retire_tag
);

    localparam ROB_ENTRY_STATE_WIDTH       = 2;
    localparam ROB_ENTRY_STATE_INVALID     = 2'b00;
    localparam ROB_ENTRY_STATE_PENDING     = 2'b01;
    localparam ROB_ENTRY_STATE_LSU_PENDING = 2'b10;
    localparam ROB_ENTRY_STATE_RETIRABLE   = 2'b11;

    // ROB entry consists of the following:
    // redirect:    Asserted by branches or instructions that cause exceptions
    // lsu_op:      Indicates if the op is a load/store op
    // op:          What operation is the instruction doing?
    // pc:          Address of the instruction (to rollback on exception
    // rdest:       The destination register
    // addr:        Destination address for branch
    // data:        The data for the destination register
    // state:       State of the ROB entry
    logic                              rob_entry_redirect_r [0:OPTN_ROB_DEPTH-1];
    logic                              rob_entry_lsu_op_r   [0:OPTN_ROB_DEPTH-1];
    logic [`PCYN_ROB_OP_WIDTH-1:0]     rob_entry_op_r       [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]        rob_entry_pc_r       [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_REGMAP_IDX_WIDTH-1:0]  rob_entry_rdest_r    [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]        rob_entry_addr_r     [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]        rob_entry_data_r     [0:OPTN_ROB_DEPTH-1];
    logic [ROB_ENTRY_STATE_WIDTH-1:0]  rob_entry_state_r    [0:OPTN_ROB_DEPTH-1];

    // It's convenient to add an extra bit for the head and tail pointers so that they may wrap around and allow for easier queue full/empty detection
    logic [ROB_IDX_WIDTH:0]            rob_head_r;
    logic [ROB_IDX_WIDTH:0]            rob_tail_r;
    logic [ROB_IDX_WIDTH:0]            rob_tail_next;
    logic [ROB_IDX_WIDTH:0]            rob_head_next;
    logic [ROB_IDX_WIDTH-1:0]          rob_head_addr;
    logic [ROB_IDX_WIDTH-1:0]          rob_tail_addr;
    logic                              rob_full_r;
    logic                              rob_rename_en;
    logic                              rob_retire_en;
    logic [OPTN_ROB_DEPTH-1:0]         rob_dispatch_en;
    logic [OPTN_ROB_DEPTH-1:0]         rob_dispatch_select_r;
    logic                              redirect_r;
    logic                              redirect;
    logic [OPTN_ADDR_WIDTH-1:0]        redirect_addr_mux;
    logic                              rob_lsu_pending;
    logic                              rob_head_is_ld;
    logic                              rob_head_is_st;
    logic [ROB_ENTRY_STATE_WIDTH-1:0]  rob_entry_state_next   [0:OPTN_ROB_DEPTH-1];
    logic                              rob_lsu_retired_ack    [0:OPTN_ROB_DEPTH-1];
    logic                              rob_entry_redirect_mux [0:OPTN_ROB_DEPTH-1];
    logic                              rob_entry_lsu_op_mux   [0:OPTN_ROB_DEPTH-1];
    logic [`PCYN_ROB_OP_WIDTH-1:0]     rob_entry_op_mux       [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]        rob_entry_pc_mux       [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_REGMAP_IDX_WIDTH-1:0]  rob_entry_rdest_mux    [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]        rob_entry_addr_mux     [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]        rob_entry_data_mux     [0:OPTN_ROB_DEPTH-1];
    logic                              rob_entry_retirable    [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]        rs_src_data_mux        [0:1];
    logic                              rs_src_rdy             [0:1];
    logic                              lsu_retire_lq_en;
    logic                              lsu_retire_sq_en;

    assign rob_rename_en       = i_regmap_rename_en && !rob_full_r;
    assign rob_retire_en       = rob_entry_state_r[rob_head_addr] == ROB_ENTRY_STATE_RETIRABLE;
    assign rob_dispatch_en     = {(OPTN_ROB_DEPTH){i_rob_enq_en}} & rob_dispatch_select_r;
    assign rob_lsu_pending     = rob_entry_state_r[rob_head_addr] == ROB_ENTRY_STATE_LSU_PENDING;
    assign rob_head_is_ld      = rob_entry_op_r[rob_head_addr] == `PCYN_ROB_OP_LD;
    assign rob_head_is_st      = rob_entry_op_r[rob_head_addr] == `PCYN_ROB_OP_ST;

    assign rob_tail_addr       = rob_tail_r[ROB_IDX_WIDTH-1:0];
    assign rob_head_addr       = rob_head_r[ROB_IDX_WIDTH-1:0];
    assign rob_tail_next       = redirect_r ? {(ROB_IDX_WIDTH+1){1'b0}} : rob_tail_r + (ROB_IDX_WIDTH+1)'(rob_rename_en);
    assign rob_head_next       = redirect_r ? {(ROB_IDX_WIDTH+1){1'b0}} : rob_head_r + (ROB_IDX_WIDTH+1)'(rob_retire_en);

    // Outputs
    assign o_rob_stall         = rob_full_r;
    assign o_regmap_rename_tag = rob_tail_addr;
    assign o_redirect          = redirect_r;

    // Increment the tail pointer to reserve an entry when the Dispatcher is in the renaming cycle
    // and the ROB is not full. On the next cycle the entry will be filled. Reset if redirect asserted.
    // Increment the head pointer if the instruction is retirable  and the ROB is not
    // empty (of course this should never be the case). Reset if redirect asserted
    always_ff @(posedge clk) begin
        if (!n_rst) begin
            rob_tail_r <= {(ROB_IDX_WIDTH+1){1'b0}};
            rob_head_r <= {(ROB_IDX_WIDTH+1){1'b0}};
        end else begin
            rob_tail_r <= rob_tail_next;
            rob_head_r <= rob_head_next;
        end
    end

    always_ff @(posedge clk) begin
        if (!n_rst) rob_full_r <= 1'b0;
        else        rob_full_r <= redirect_r ? 1'b0 : {~rob_tail_next[ROB_IDX_WIDTH], rob_tail_next[ROB_IDX_WIDTH-1:0]} == rob_head_next;
    end

    // If the instruction to be retired generated a branch/mispredict then assert the redirect signal and address
    always_comb begin
        redirect_addr_mux = (rob_entry_op_r[rob_head_addr] == `PCYN_ROB_OP_BR) ? rob_entry_addr_r[rob_head_addr] : rob_entry_pc_r[rob_head_addr];
        redirect          = rob_retire_en && rob_entry_redirect_r[rob_head_addr];
    end

    always_ff @(posedge clk) begin
        o_redirect_addr <= redirect_addr_mux;
    end

    always_ff @(posedge clk) begin
        if (!n_rst) redirect_r <= 1'b0;
        else        redirect_r <= redirect;
    end

    // Generate a one-hot vector selecting which ROB entry dispatcher enqueues a new instruction into
    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_ROB_DEPTH; i++) begin
            rob_dispatch_select_r[i] <= rob_rename_en && (ROB_IDX_WIDTH'(i) == rob_tail_addr);
        end
    end

    // Check CDB inputs for matching tags and determine which entry can be marked as retirable
    // Also mux in address, data and redirect information from CDB
    // Mux lsu_op, op, pc, & rdest values from dispatcher when enqueuing in an ROB entry
    always_comb begin
        for (int rob_idx = 0; rob_idx < OPTN_ROB_DEPTH; rob_idx++) begin
            rob_lsu_retired_ack[rob_idx]    = (ROB_IDX_WIDTH'(rob_idx) == rob_head_addr) && rob_lsu_pending && ((rob_head_is_ld && i_lsu_retire_lq_ack) || (rob_head_is_st && i_lsu_retire_sq_ack));
            rob_entry_redirect_mux[rob_idx] = rob_lsu_retired_ack[rob_idx] ? i_lsu_retire_misspeculated : rob_entry_redirect_r[rob_idx];
            rob_entry_lsu_op_mux[rob_idx]   = rob_dispatch_en[rob_idx] ? (i_rob_enq_op == `PCYN_ROB_OP_LD || i_rob_enq_op == `PCYN_ROB_OP_ST) : rob_entry_lsu_op_r[rob_idx];
            rob_entry_op_mux[rob_idx]       = rob_dispatch_en[rob_idx] ? i_rob_enq_op : rob_entry_op_r[rob_idx];
            rob_entry_pc_mux[rob_idx]       = rob_dispatch_en[rob_idx] ? i_rob_enq_pc : rob_entry_pc_r[rob_idx];
            rob_entry_rdest_mux[rob_idx]    = rob_dispatch_en[rob_idx] ? i_rob_enq_rdest : rob_entry_rdest_r[rob_idx];
            rob_entry_addr_mux[rob_idx]     = rob_entry_addr_r[rob_idx];
            rob_entry_data_mux[rob_idx]     = rob_entry_data_r[rob_idx];
            rob_entry_retirable[rob_idx]    = 1'b0;

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                logic cdb_tag_match;
                cdb_tag_match                   = i_cdb_en[cdb_idx] && (ROB_IDX_WIDTH'(rob_idx) == i_cdb_tag[cdb_idx]);
                rob_entry_addr_mux[rob_idx]     = cdb_tag_match ? i_cdb_addr[cdb_idx] : rob_entry_addr_mux[rob_idx];
                rob_entry_data_mux[rob_idx]     = cdb_tag_match ? i_cdb_data[cdb_idx] : rob_entry_data_mux[rob_idx];
                rob_entry_redirect_mux[rob_idx] = cdb_tag_match ? i_cdb_redirect[cdb_idx] : rob_entry_redirect_mux[rob_idx];
                rob_entry_retirable[rob_idx]    = cdb_tag_match || rob_entry_retirable[rob_idx];
            end

            // Clear the redirect bit if an instruction is being enqueued at the entry
            rob_entry_redirect_mux[rob_idx] = !rob_dispatch_en[rob_idx] && rob_entry_redirect_mux[rob_idx];
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_ROB_DEPTH; i++) begin
            rob_entry_redirect_r[i] <= rob_entry_redirect_mux[i];
            rob_entry_lsu_op_r[i]   <= rob_entry_lsu_op_mux[i];
            rob_entry_op_r[i]       <= rob_entry_op_mux[i];
            rob_entry_pc_r[i]       <= rob_entry_pc_mux[i];
            rob_entry_rdest_r[i]    <= rob_entry_rdest_mux[i];
            rob_entry_addr_r[i]     <= rob_entry_addr_mux[i];
            rob_entry_data_r[i]     <= rob_entry_data_mux[i];
        end
    end

    // ROB entry next state logic
    // Each ROB entry progresses through up to 4 states (at least 3 of them, LSU ops go through an extra state)
    // ROB_ENTRY_STATE_PENDING: From INVALID to PENDING when a ROB entry is enqueued
    // ROB_ENTRY_STATE_LSU_PENDING: LSU ops are put in the LSU_PENDING state waiting for an ack from the LQ or SQ
    // This is needed to allow the LQ to signal back whether the load has been misspeculated and for the SQ to acknowledge that store has been written out to memeory
    // In both cases the LQ and SQ dequeue the op
    // ROB_ENTRY_STATE_RETIRABLE: This indicates that the op has completed execution and can be retired when it reaches the head of the ROB
    always_comb begin
        for (int i = 0; i < OPTN_ROB_DEPTH; i++) begin
            logic [ROB_ENTRY_STATE_WIDTH-1:0] rob_entry_state_lsu_pending_mux;
            rob_entry_state_lsu_pending_mux = rob_entry_lsu_op_r[i] ? ROB_ENTRY_STATE_LSU_PENDING : ROB_ENTRY_STATE_RETIRABLE;

            case (rob_entry_state_r[i])
                ROB_ENTRY_STATE_INVALID:     rob_entry_state_next[i] = rob_dispatch_en[i] ? ROB_ENTRY_STATE_PENDING : ROB_ENTRY_STATE_INVALID;
                ROB_ENTRY_STATE_PENDING:     rob_entry_state_next[i] = rob_entry_retirable[i] ? rob_entry_state_lsu_pending_mux : ROB_ENTRY_STATE_PENDING;
                ROB_ENTRY_STATE_LSU_PENDING: rob_entry_state_next[i] = rob_lsu_retired_ack[i] ? ROB_ENTRY_STATE_RETIRABLE : ROB_ENTRY_STATE_LSU_PENDING;
                ROB_ENTRY_STATE_RETIRABLE:   rob_entry_state_next[i] = (rob_head_addr == ROB_IDX_WIDTH'(i) && rob_retire_en) ? ROB_ENTRY_STATE_INVALID : ROB_ENTRY_STATE_RETIRABLE;
                default:                     rob_entry_state_next[i] = ROB_ENTRY_STATE_INVALID;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_ROB_DEPTH; i++) begin
            if (!n_rst) rob_entry_state_r[i] <= ROB_ENTRY_STATE_INVALID;
            else        rob_entry_state_r[i] <= redirect ? ROB_ENTRY_STATE_INVALID : rob_entry_state_next[i];
        end
    end

    // Getting the right source register tags/data is tricky. If the register map has ready data then that must be used
    // Otherwise the ROB entry corresponding to the tag in the register map for the source register is looked up and the data,
    // if available, is retrieved from that entry. If it's not available then the instruction must wait for the tag to be broadcast
    // on the CDB. Now if there is something available on the CDB in the same cycle and it matches the tag from the register map,
    // then that value must be used over the ROB data.
    // An instructions source ready bits can be overrided to 1 if that instruction has no use for that source which allows it to skip waiting for that source in RS
    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            logic [ROB_IDX_WIDTH-1:0] rob_tag;
            logic                     rob_lookup_rdy [0:1];
            rob_tag                  = i_rob_lookup_tag[src_idx];
            rob_lookup_rdy[src_idx]  = i_rob_lookup_rdy[src_idx] || i_rob_lookup_rdy_ovrd[src_idx];

            rs_src_data_mux[src_idx] = rob_entry_data_r[rob_tag];
            rs_src_rdy[src_idx]      = rob_lookup_rdy[src_idx] || (rob_entry_state_r[rob_tag] == ROB_ENTRY_STATE_RETIRABLE) || (rob_entry_state_r[rob_tag] == ROB_ENTRY_STATE_LSU_PENDING);

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                logic cdb_lookup_bypass;
                cdb_lookup_bypass        = i_cdb_en[cdb_idx] && (i_cdb_tag[cdb_idx] == rob_tag);
                rs_src_data_mux[src_idx] = cdb_lookup_bypass ? i_cdb_data[cdb_idx] : rs_src_data_mux[src_idx];
                rs_src_rdy[src_idx]      = cdb_lookup_bypass || rs_src_rdy[src_idx];
            end

            rs_src_data_mux[src_idx] = rob_lookup_rdy[src_idx] ? i_rob_lookup_data[src_idx] : rs_src_data_mux[src_idx];
        end
    end

    always_ff @(posedge clk) begin
        if (!i_rs_stall) begin
            o_rs_src_data <= rs_src_data_mux;
            o_rs_src_tag  <= i_rob_lookup_tag;
            o_rs_src_rdy  <= rs_src_rdy;
        end
    end

    // Let the Regmap know that this instruction is retiring in order to update the destination register mapping
    always_ff @(posedge clk) begin
        o_regmap_retire_data  <= rob_entry_data_r[rob_head_addr];
        o_regmap_retire_rdest <= rob_entry_rdest_r[rob_head_addr];
        o_regmap_retire_tag   <= rob_head_addr;
    end

    always_ff @(posedge clk) begin
        if (!n_rst) o_regmap_retire_en <= 1'b0;
        else        o_regmap_retire_en <= rob_retire_en;
    end

    // Let the LSU know that the instruction at the head of the ROB is ready to be retired and is waiting for an ack from the LSU
    always_comb begin
        lsu_retire_lq_en = rob_lsu_pending && rob_head_is_ld && ~i_lsu_retire_lq_ack;
        lsu_retire_sq_en = rob_lsu_pending && rob_head_is_st && ~i_lsu_retire_sq_ack;
    end

    always_ff @(posedge clk) begin
        o_lsu_retire_tag <= rob_head_addr;
    end

    always_ff @(posedge clk) begin
        o_lsu_retire_lq_en <= redirect_r ? 1'b0 : lsu_retire_lq_en;
        o_lsu_retire_sq_en <= redirect_r ? 1'b0 : lsu_retire_sq_en;
    end

endmodule
