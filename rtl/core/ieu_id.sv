// Integer Execution Unit - Decode Stage

`include "common.svh"
import procyon_types::*;

module ieu_id (
    input  procyon_opcode_t     i_opcode,
    input  procyon_addr_t       i_iaddr,
/* verilator lint_off UNUSED */
    input  procyon_data_t       i_insn,
/* verilator lint_on  UNUSED */
    input  procyon_data_t       i_src_a,
    input  procyon_data_t       i_src_b,
    input  procyon_tag_t        i_tag,
    input                       i_valid,

    output procyon_alu_func_t   o_alu_func,
    output procyon_data_t       o_src_a,
    output procyon_data_t       o_src_b,
    output procyon_addr_t       o_iaddr,
    output procyon_data_t       o_imm_b,
    output procyon_shamt_t      o_shamt,
    output procyon_tag_t        o_tag,
    output logic                o_jmp,
    output logic                o_br,
    output logic                o_valid
);

    procyon_data_t      imm_i;
    procyon_data_t      imm_b;
    procyon_data_t      imm_u;
    procyon_data_t      imm_j;
    procyon_alu_func_t  alu_func_srx;
    procyon_alu_func_t  alu_func_asx;
    procyon_alu_func_t  alu_func;
    logic [1:0]         alu_func_sel;
    logic               is_br;
    logic               is_jal;
    logic               is_jalr;
    logic               is_op;
    logic               is_opimm;
    logic               is_lui;
    logic               is_auipc;

    assign is_br        = i_opcode == OPCODE_BRANCH;
    assign is_jal       = i_opcode == OPCODE_JAL;
    assign is_jalr      = i_opcode == OPCODE_JALR;
    assign is_op        = i_opcode == OPCODE_OP;
    assign is_opimm     = i_opcode == OPCODE_OPIMM;
    assign is_lui       = i_opcode == OPCODE_LUI;
    assign is_auipc     = i_opcode == OPCODE_AUIPC;

    assign alu_func_sel = {is_br, is_op | is_opimm};

    // Determine ALU FUNC for certain ops depending on instruction bit 30
    assign alu_func_srx = i_insn[30] ? ALU_FUNC_SRA : ALU_FUNC_SRL;
    assign alu_func_asx = i_insn[30] ? ALU_FUNC_SUB : ALU_FUNC_ADD;

    // Generate immediates
    assign imm_i        = {{(`DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[24:21], i_insn[20]};
    assign imm_b        = {{(`DATA_WIDTH-12){i_insn[31]}}, i_insn[7], i_insn[30:25], i_insn[11:8], 1'b0};
    assign imm_u        = {{(`DATA_WIDTH-31){i_insn[31]}}, i_insn[30:25], i_insn[24:21], i_insn[20], i_insn[19:12], {12{1'b0}}};
    assign imm_j        = {{(`DATA_WIDTH-20){i_insn[31]}}, i_insn[19:12], i_insn[20], i_insn[30:25], i_insn[24:21], 1'b0};

    // Assign static outputs
    assign o_iaddr      = i_iaddr;
    assign o_imm_b      = imm_b;
    assign o_tag        = i_tag;
    assign o_valid      = i_valid;

    assign o_br         = is_br & (i_insn[14:12] != 3'b010) & (i_insn[14:12] != 3'b011);
    assign o_jmp        = is_jal | is_jalr;
    assign o_shamt      = is_op ? i_src_b[4:0] : i_insn[24:20];
    assign o_src_a      = mux4_data(i_src_a, {(`DATA_WIDTH){1'b0}}, i_iaddr, i_src_a, {is_auipc | is_jal, is_lui});
    assign o_src_b      = mux4_data(is_jal ? imm_j : imm_u, imm_i, i_src_b, i_src_b, {is_op | is_br, is_opimm | is_jalr});
    assign o_alu_func   = alu_func;

    // Decode based on opcode and funct3 fields
    always_comb begin
        case (i_insn[14:12])
            3'b000: alu_func = procyon_alu_func_t'(mux4_4b(ALU_FUNC_ADD, alu_func_asx, ALU_FUNC_EQ, ALU_FUNC_ADD, {is_br, is_op}));
            3'b001: alu_func = procyon_alu_func_t'(mux4_4b(ALU_FUNC_ADD, ALU_FUNC_SLL, ALU_FUNC_NE, ALU_FUNC_ADD, alu_func_sel));
            3'b010: alu_func = is_op | is_opimm ? ALU_FUNC_LT : ALU_FUNC_ADD;
            3'b011: alu_func = is_op | is_opimm ? ALU_FUNC_LTU : ALU_FUNC_ADD;
            3'b100: alu_func = procyon_alu_func_t'(mux4_4b(ALU_FUNC_ADD, ALU_FUNC_XOR, ALU_FUNC_LT, ALU_FUNC_ADD, alu_func_sel));
            3'b101: alu_func = procyon_alu_func_t'(mux4_4b(ALU_FUNC_ADD, alu_func_srx, ALU_FUNC_GE, ALU_FUNC_ADD, alu_func_sel));
            3'b110: alu_func = procyon_alu_func_t'(mux4_4b(ALU_FUNC_ADD, ALU_FUNC_OR, ALU_FUNC_LTU, ALU_FUNC_ADD, alu_func_sel));
            3'b111: alu_func = procyon_alu_func_t'(mux4_4b(ALU_FUNC_ADD, ALU_FUNC_AND, ALU_FUNC_GEU, ALU_FUNC_ADD, alu_func_sel));
        endcase
    end

endmodule
