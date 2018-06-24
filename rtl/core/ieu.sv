// Integer Execution Unit
// Encapsulates the ID and EX stages
// Writes the result of the EX stage to the CDB when it is available

`include "common.svh"
import procyon_types::*;

module ieu (
    input  logic             clk,
    input  logic             n_rst,

    input  logic             i_flush,

    // Common Data Bus
    output logic             o_cdb_en,
    output logic             o_cdb_redirect,
    output procyon_data_t    o_cdb_data,
    output procyon_addr_t    o_cdb_addr,
    output procyon_tag_t     o_cdb_tag,

    // Reservation station interface
    input  logic             i_fu_valid,
    input  procyon_opcode_t  i_fu_opcode,
    input  procyon_addr_t    i_fu_iaddr,
    input  procyon_data_t    i_fu_insn,
    input  procyon_data_t    i_fu_src_a,
    input  procyon_data_t    i_fu_src_b,
    input  procyon_tag_t     i_fu_tag,
    output logic             o_fu_stall
);

    // ID -> EX pipeline registers
    typedef struct packed {
        procyon_alu_func_t   alu_func;
        procyon_data_t       src_a;
        procyon_data_t       src_b;
        procyon_addr_t       iaddr;
        procyon_data_t       imm_b;
        procyon_shamt_t      shamt;
        procyon_tag_t        tag;
        logic                jmp;
        logic                br;
        logic                valid;
    } ieu_id_t;

    ieu_id_t                 ieu_id;

    assign o_fu_stall        = 1'b0;

    ieu_id ieu_id_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_opcode(i_fu_opcode),
        .i_iaddr(i_fu_iaddr),
        .i_insn(i_fu_insn),
        .i_src_a(i_fu_src_a),
        .i_src_b(i_fu_src_b),
        .i_tag(i_fu_tag),
        .i_valid(i_fu_valid),
        .o_alu_func(ieu_id.alu_func),
        .o_src_a(ieu_id.src_a),
        .o_src_b(ieu_id.src_b),
        .o_iaddr(ieu_id.iaddr),
        .o_imm_b(ieu_id.imm_b),
        .o_shamt(ieu_id.shamt),
        .o_tag(ieu_id.tag),
        .o_jmp(ieu_id.jmp),
        .o_br(ieu_id.br),
        .o_valid(ieu_id.valid)
    );

    ieu_ex ieu_ex_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_alu_func(ieu_id.alu_func),
        .i_src_a(ieu_id.src_a),
        .i_src_b(ieu_id.src_b),
        .i_iaddr(ieu_id.iaddr),
        .i_imm_b(ieu_id.imm_b),
        .i_shamt(ieu_id.shamt),
        .i_tag(ieu_id.tag),
        .i_jmp(ieu_id.jmp),
        .i_br(ieu_id.br),
        .i_valid(ieu_id.valid),
        .o_data(o_cdb_data),
        .o_addr(o_cdb_addr),
        .o_tag(o_cdb_tag),
        .o_redirect(o_cdb_redirect),
        .o_valid(o_cdb_en)
    );

endmodule
