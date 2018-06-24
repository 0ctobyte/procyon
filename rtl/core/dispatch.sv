// Dispatch module
// Decodes and dispatches instructions over two cycles
// Cycle 1:
// * Decodes instruction
// * Renames destination register in Register Map and reserves and entry in the ROB
// * Lookup source register from the Register Map
// Cycle 2:
// * Registers reservation staton enqueue signals
// * Lookup source register in ROB and merges them with Register Map sources looked up in the previous cycle
// * Enqueue instruction in ROB

`include "common.svh"
import procyon_types::*;

module dispatch (
    input  logic                 clk,
    input  logic                 n_rst,

    input  logic                 i_flush,
    input  logic                 i_rob_stall,
    input  logic                 i_rs_stall,

    // Fetch interface
    input  procyon_addr_t        i_dispatch_pc,
    input  procyon_data_t        i_dispatch_insn,
    input  logic                 i_dispatch_valid,
    output logic                 o_dispatch_stall,

    // Register Map lookup interface
    output procyon_reg_t         o_regmap_lookup_rsrc [0:1],
    output logic                 o_regmap_lookup_valid,

    // Register Map rename interface
    output procyon_reg_t         o_regmap_rename_rdest,
    output logic                 o_regmap_rename_en,

    // ROB tag used to rename destination register in the Register Map
    input  procyon_tag_t         i_rob_dst_tag,

    // Override ready signals when ROB looks up source registers
    output logic                 o_rob_lookup_rdy_ovrd [0:1],

    // ROB enqueue interface
    output logic                 o_rob_enq_en,
    output procyon_rob_op_t      o_rob_enq_op,
    output procyon_addr_t        o_rob_enq_pc,
    output procyon_reg_t         o_rob_enq_rdest,

    // Reservation Station enqueue interface
    output logic                 o_rs_en,
    output procyon_opcode_t      o_rs_opcode,
    output procyon_addr_t        o_rs_pc,
    output procyon_data_t        o_rs_insn,
    output procyon_tag_t         o_rs_dst_tag
);

    logic                        rs_en;
    procyon_opcode_t             rs_opcode;
    procyon_addr_t               rs_pc;
    procyon_data_t               rs_insn;
    procyon_tag_t                rs_dst_tag;

    assign o_dispatch_stall      = i_rob_stall;

    // Decode & Rename (first cycle)
    // - Decodes intstruction
    // - Look up source operands in Register Map (bypassing retired destination register if needed)
    // - Renames destination register of instruction
    decode_rename decode_rename_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_rob_stall(i_rob_stall),
        .i_rs_stall(i_rs_stall),
        .i_dispatch_pc(i_dispatch_pc),
        .i_dispatch_insn(i_dispatch_insn),
        .i_dispatch_valid(i_dispatch_valid),
        .i_rob_dst_tag(i_rob_dst_tag),
        .o_regmap_lookup_rsrc(o_regmap_lookup_rsrc),
        .o_regmap_lookup_valid(o_regmap_lookup_valid),
        .o_regmap_rename_rdest(o_regmap_rename_rdest),
        .o_regmap_rename_en(o_regmap_rename_en),
        .o_rob_lookup_rdy_ovrd(o_rob_lookup_rdy_ovrd),
        .o_rob_enq_en(o_rob_enq_en),
        .o_rob_enq_pc(o_rob_enq_pc),
        .o_rob_enq_op(o_rob_enq_op),
        .o_rob_enq_rdest(o_rob_enq_rdest),
        .o_rs_en(rs_en),
        .o_rs_opcode(rs_opcode),
        .o_rs_pc(rs_pc),
        .o_rs_insn(rs_insn),
        .o_rs_dst_tag(rs_dst_tag)
    );

    // Map & Dispatch (second cycle)
    // - Take Register Map source operand lookup tags and lookup source operands in ROB (bypassing from CDB if needed)
    // - Enqueues instructions in Reorder Buffer
    map_dispatch map_dispatch_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_rob_stall(i_rob_stall),
        .i_rs_stall(i_rs_stall),
        .i_rs_en(rs_en),
        .i_rs_opcode(rs_opcode),
        .i_rs_pc(rs_pc),
        .i_rs_insn(rs_insn),
        .i_rs_dst_tag(rs_dst_tag),
        .o_rs_en(o_rs_en),
        .o_rs_opcode(o_rs_opcode),
        .o_rs_pc(o_rs_pc),
        .o_rs_insn(o_rs_insn),
        .o_rs_dst_tag(o_rs_dst_tag)
    );

endmodule
