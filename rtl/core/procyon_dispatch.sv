/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Dispatch module
// Decodes and dispatches instructions over two cycles
// Cycle 1:
// * Decodes instruction
// * Renames destination register in Register Map and reserves and entry in the ROB
// * Lookup source register from the Register Map
// Cycle 2:
// * Updates ROB with new op, pc and rdest
// * Updates reservation station with new op

`include "procyon_constants.svh"

module procyon_dispatch #(
    parameter OPTN_DATA_WIDTH       = 32,
    parameter OPTN_ADDR_WIDTH       = 32,
    parameter OPTN_REGMAP_IDX_WIDTH = 5,
    parameter OPTN_ROB_IDX_WIDTH    = 5
)(
    input  logic                             clk,
    input  logic                             n_rst,

    input  logic                             i_flush,
    input  logic                             i_rob_stall,
    input  logic                             i_rs_stall,

    // Fetch interface
    input  logic [OPTN_ADDR_WIDTH-1:0]       i_dispatch_pc,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_dispatch_insn,
    input  logic                             i_dispatch_valid,
    output logic                             o_dispatch_stall,

    // Register Map lookup interface
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0] o_regmap_lookup_rsrc [0:1],

    // Register Map rename interface
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0] o_regmap_rename_rdest,
    output logic                             o_regmap_rename_en,

    // ROB tag used to rename destination register in the Register Map
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]    i_rob_dst_tag,

    // Override ready signals when ROB looks up source registers
    output logic                             o_rob_lookup_rdy_ovrd [0:1],

    // ROB enqueue interface
    output logic                             o_rob_enq_en,
    output logic [`PCYN_ROB_OP_WIDTH-1:0]    o_rob_enq_op,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_rob_enq_pc,
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0] o_rob_enq_rdest,

    // Reservation Station enqueue interface
    output logic                             o_rs_en,
    output logic [`PCYN_OPCODE_WIDTH-1:0]    o_rs_opcode,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_rs_pc,
    output logic [OPTN_DATA_WIDTH-1:0]       o_rs_insn,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]    o_rs_dst_tag
);

    logic dispatch_stall;
    assign dispatch_stall = i_rob_stall | i_rs_stall;
    assign o_dispatch_stall = dispatch_stall;

    logic n_flush;
    logic n_rs_stall;
    logic n_rob_stall;

    assign n_flush = ~i_flush;
    assign n_rs_stall = ~i_rs_stall;
    assign n_rob_stall = ~i_rob_stall;

    // The rs_dispatch_en should be set to i_dispatch_valid if there are no stalls. If the RS is stalled we must maintain
    // the previous value of the register. Otherwise, if the ROB is stalled we need to clear the register in order to
    // punch a bubble in the RS enqueue interface so the RS does not enqueue anything in that cycle. If i_flush is
    // asserted then this register will be cleared.
    logic rs_dispatch_en;
    logic rs_dispatch_en_r;

    assign rs_dispatch_en = n_flush & (i_rs_stall ? rs_dispatch_en_r : (n_rob_stall & i_dispatch_valid));
    procyon_srff #(1) rs_dispatch_en_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(rs_dispatch_en), .i_reset(1'b0), .o_q(rs_dispatch_en_r));

    assign o_rs_en = rs_dispatch_en_r;

    // The RS dispatch registers should not be overwritten if the RS is stalled
    procyon_ff #(OPTN_ADDR_WIDTH) o_rs_pc_ff (.clk(clk), .i_en(n_rs_stall), .i_d(i_dispatch_pc), .o_q(o_rs_pc));
    procyon_ff #(OPTN_DATA_WIDTH) o_rs_insn_ff (.clk(clk), .i_en(n_rs_stall), .i_d(i_dispatch_insn), .o_q(o_rs_insn));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_rs_dst_tag_ff (.clk(clk), .i_en(n_rs_stall), .i_d(i_rob_dst_tag), .o_q(o_rs_dst_tag));

    logic [`PCYN_OPCODE_WIDTH-1:0] opcode;
    assign opcode = i_dispatch_insn[6:0];
    procyon_ff #(`PCYN_OPCODE_WIDTH) o_rs_opcode_ff (.clk(clk), .i_en(n_rs_stall), .i_d(opcode), .o_q(o_rs_opcode));

    // opcode comparators
    logic is_opimm;
    logic is_lui;
    logic is_auipc;
    logic is_op;
    logic is_jal;
    logic is_jalr;
    logic is_branch;
    logic is_load;
    logic is_store;

    assign is_opimm = (opcode == `PCYN_OPCODE_OPIMM);
    assign is_lui = (opcode == `PCYN_OPCODE_LUI);
    assign is_auipc = (opcode == `PCYN_OPCODE_AUIPC);
    assign is_op = (opcode == `PCYN_OPCODE_OP);
    assign is_jal = (opcode == `PCYN_OPCODE_JAL);
    assign is_jalr = (opcode == `PCYN_OPCODE_JALR);
    assign is_branch = (opcode == `PCYN_OPCODE_BRANCH);
    assign is_load = (opcode == `PCYN_OPCODE_LOAD);
    assign is_store = (opcode == `PCYN_OPCODE_STORE);

    // ROB lookup source ready override signals. This indicates whether the source operand should be set to 1 for a
    // certain set of ops
    assign o_rob_lookup_rdy_ovrd[0] = ~(is_opimm | is_op | is_jalr | is_branch | is_load | is_store);
    assign o_rob_lookup_rdy_ovrd[1] = ~(is_op | is_branch | is_store);

    // Don't enqueue anything in the ROB if any one of i_flush, i_rs_stall or i_rob_stall are asserted.
    logic rob_dispatch_en;
    assign rob_dispatch_en = n_flush & n_rs_stall & n_rob_stall & i_dispatch_valid;
    procyon_srff #(1) o_rob_enq_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(rob_dispatch_en), .i_reset(1'b0), .o_q(o_rob_enq_en));

    // The ROB enqueue registers should not be overwritten if the ROB stalls
    procyon_ff #(OPTN_ADDR_WIDTH) o_rob_enq_pc_ff (.clk(clk), .i_en(n_rob_stall), .i_d(i_dispatch_pc), .o_q(o_rob_enq_pc));

    logic [OPTN_REGMAP_IDX_WIDTH-1:0] rdest;
    logic rob_rdest_sel;
    logic [OPTN_REGMAP_IDX_WIDTH-1:0] rob_enq_rdest;

    assign rdest = i_dispatch_insn[11:7];
    assign rob_rdest_sel = is_opimm | is_lui | is_auipc | is_op | is_jal | is_jalr | is_load;
    assign rob_enq_rdest = rob_rdest_sel ? rdest : '0;
    procyon_ff #(OPTN_REGMAP_IDX_WIDTH) o_rob_enq_rdest_ff (.clk(clk), .i_en(n_rob_stall), .i_d(rob_enq_rdest), .o_q(o_rob_enq_rdest));

    logic [`PCYN_ROB_OP_WIDTH-1:0] rob_enq_op;

    always_comb begin
        logic [1:0] rob_op_sel;

        rob_op_sel = {is_store | is_branch | is_jal | is_jalr, is_load | is_branch | is_jal | is_jalr};
        case (rob_op_sel)
            2'b00: rob_enq_op = `PCYN_ROB_OP_INT;
            2'b01: rob_enq_op = `PCYN_ROB_OP_LD;
            2'b10: rob_enq_op = `PCYN_ROB_OP_ST;
            2'b11: rob_enq_op = `PCYN_ROB_OP_BR;
        endcase
    end

    procyon_ff #(`PCYN_ROB_OP_WIDTH) o_rob_enq_op_ff (.clk(clk), .i_en(n_rob_stall), .i_d(rob_enq_op), .o_q(o_rob_enq_op));

    // Interface to Register Map to lookup source operands
    logic [OPTN_REGMAP_IDX_WIDTH-1:0] rsrc [0:1];
    assign rsrc[0] = i_dispatch_insn[19:15];
    assign rsrc[1] = i_dispatch_insn[24:20];
    assign o_regmap_lookup_rsrc = rsrc;

    // Interface to Register Map to rename destination register for new instruction
    assign o_regmap_rename_rdest = rob_enq_rdest;
    assign o_regmap_rename_en = ~dispatch_stall & i_dispatch_valid;

endmodule
