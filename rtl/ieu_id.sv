// Integer Execution Unit - Decode Stage

import types::*;

module ieu_id #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter TAG_WIDTH  = 6
) (
    input  logic                  clk,
    input  logic                  n_rst,

    input  opcode_t               i_opcode,
    input  logic [ADDR_WIDTH-1:0] i_iaddr,
    input  logic [DATA_WIDTH-1:0] i_insn,
    input  logic [DATA_WIDTH-1:0] i_src_a,
    input  logic [DATA_WIDTH-1:0] i_src_b,
    input  logic [TAG_WIDTH-1:0]  i_tag,
    input                         i_valid,

    output alu_func_t             o_alu_func,
    output logic [DATA_WIDTH-1:0] o_src_a,
    output logic [DATA_WIDTH-1:0] o_src_b,
    output logic [ADDR_WIDTH-1:0] o_iaddr,
    output logic [DATA_WIDTH-1:0] o_imm_b,
    output logic [4:0]            o_shamt,
    output logic [TAG_WIDTH-1:0]  o_tag,
    output logic                  o_jmp,
    output logic                  o_br,
    output logic                  o_valid
);

    logic [DATA_WIDTH-1:0] imm_i;
    logic [DATA_WIDTH-1:0] imm_b;
    logic [DATA_WIDTH-1:0] imm_u;
    logic [DATA_WIDTH-1:0] imm_j;

    alu_func_t alu_func_srx;
    alu_func_t alu_func_asx;

    // Determine ALU FUNC for certain ops depending on instruction bit 30
    assign alu_func_srx = i_insn[30] ? ALU_FUNC_SRA : ALU_FUNC_SRL; 
    assign alu_func_asx = i_insn[30] ? ALU_FUNC_SUB : ALU_FUNC_ADD;

    // Generate immediates
    assign imm_i = {{(DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[24:21], i_insn[20]};
    assign imm_b = {{(DATA_WIDTH-12){i_insn[31]}}, i_insn[7], i_insn[30:25], i_insn[11:8], 1'b0};
    assign imm_u = {{(DATA_WIDTH-31){i_insn[31]}}, i_insn[30:25], i_insn[24:21], i_insn[20], i_insn[19:12], {12{1'b0}}};
    assign imm_j = {{(DATA_WIDTH-20){i_insn[31]}}, i_insn[19:12], i_insn[20], i_insn[30:25], i_insn[24:21], 1'b0};

    // Assign static outputs
    assign o_iaddr = i_iaddr;
    assign o_imm_b = imm_b;
    assign o_tag   = i_tag;
    assign o_valid = i_valid;

    // Decode based on opcode and funct3 fields
    always_comb begin
        case (i_opcode)
            OPCODE_OPIMM: begin
                case (i_insn[14:12])
                    3'b000: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_ADD, i_src_a, imm_i, i_insn[24:20], 1'b0, 1'b0};
                    3'b001: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_SLL, i_src_a, imm_i, i_insn[24:20], 1'b0, 1'b0};
                    3'b010: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_LT,  i_src_a, imm_i, i_insn[24:20], 1'b0, 1'b0};
                    3'b011: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_LTU, i_src_a, imm_i, i_insn[24:20], 1'b0, 1'b0};
                    3'b100: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_XOR, i_src_a, imm_i, i_insn[24:20], 1'b0, 1'b0};
                    3'b101: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {alu_func_srx, i_src_a, imm_i, i_insn[24:20], 1'b0, 1'b0};
                    3'b110: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_OR,  i_src_a, imm_i, i_insn[24:20], 1'b0, 1'b0};
                    3'b111: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_AND, i_src_a, imm_i, i_insn[24:20], 1'b0, 1'b0};
                endcase
            end
            OPCODE_OP: begin
                case (i_insn[14:12])
                    3'b000: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {alu_func_asx, i_src_a, i_src_b, i_src_b[4:0], 1'b0, 1'b0};
                    3'b001: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_SLL, i_src_a, i_src_b, i_src_b[4:0], 1'b0, 1'b0};
                    3'b010: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_LT,  i_src_a, i_src_b, i_src_b[4:0], 1'b0, 1'b0};
                    3'b011: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_LTU, i_src_a, i_src_b, i_src_b[4:0], 1'b0, 1'b0};
                    3'b100: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_XOR, i_src_a, i_src_b, i_src_b[4:0], 1'b0, 1'b0};
                    3'b101: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {alu_func_srx, i_src_a, i_src_b, i_src_b[4:0], 1'b0, 1'b0};
                    3'b110: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_OR,  i_src_a, i_src_b, i_src_b[4:0], 1'b0, 1'b0};
                    3'b111: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_AND, i_src_a, i_src_b, i_src_b[4:0], 1'b0, 1'b0};
                endcase
            end
            OPCODE_BRANCH: begin
                case (i_insn[14:12])
                    3'b000:  {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_EQ,  i_src_a, i_src_b, i_insn[24:20], 1'b0, 1'b1};
                    3'b001:  {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_NE,  i_src_a, i_src_b, i_insn[24:20], 1'b0, 1'b1};
                    3'b100:  {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_LT,  i_src_a, i_src_b, i_insn[24:20], 1'b0, 1'b1};
                    3'b101:  {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_GE,  i_src_a, i_src_b, i_insn[24:20], 1'b0, 1'b1};
                    3'b110:  {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_LTU, i_src_a, i_src_b, i_insn[24:20], 1'b0, 1'b1};
                    3'b111:  {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_GEU, i_src_a, i_src_b, i_insn[24:20], 1'b0, 1'b1};
                    default: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_ADD, i_src_a, i_src_b, i_insn[24:20], 1'b0, 1'b0};
                endcase
            end
            OPCODE_LUI:   {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_ADD, 1'b0, imm_u, i_insn[24:20], 1'b0, 1'b0};
            OPCODE_AUIPC: {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_ADD, i_iaddr, imm_u, i_insn[24:20], 1'b0, 1'b0};
            OPCODE_JAL:   {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_ADD, i_iaddr, imm_j, i_insn[24:20], 1'b1, 1'b0};
            OPCODE_JALR:  {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_ADD, i_src_a, imm_i, i_insn[24:20], 1'b1, 1'b0};
            default:      {o_alu_func, o_src_a, o_src_b, o_shamt, o_jmp, o_br} = {ALU_FUNC_ADD, i_src_a, i_src_b, i_insn[24:20], 1'b0, 1'b0};
        endcase
    end

endmodule
