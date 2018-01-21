// Integer Execution Unit - Execution Stage

`include "common.svh"
import procyon_types::*;

module ieu_ex (
    input  logic                   clk,
    input  logic                   n_rst,

    input  procyon_alu_func_t      i_alu_func,
    input  procyon_data_t          i_src_a,
    input  procyon_data_t          i_src_b,
    input  procyon_addr_t          i_iaddr,
    input  procyon_data_t          i_imm_b,
    input  procyon_shamt_t         i_shamt,
    input  procyon_tag_t           i_tag,
    input  logic                   i_jmp,
    input  logic                   i_br,
    input  logic                   i_valid,

    output procyon_data_t          o_data,
    output procyon_addr_t          o_addr,
    output procyon_tag_t           o_tag,
    output logic                   o_redirect,
    output logic                   o_valid
);

    procyon_data_t            result;

    // Extended src_a for arithmetic right shifts
    logic [`DATA_WIDTH*2-1:0] e_src_a;

    // Signed src inputs
    procyon_signed_data_t     s_src_a;
    procyon_signed_data_t     s_src_b;

    assign e_src_a = {{(`DATA_WIDTH){i_src_a[`DATA_WIDTH-1]}}, i_src_a};
    assign s_src_a = i_src_a;
    assign s_src_b = i_src_b;

    // Assign outputs
    assign o_data     = i_jmp ? i_iaddr + 4 : result;
    assign o_addr     = i_jmp ? result : (i_br ? i_iaddr + i_imm_b : 'b0);
    assign o_redirect = i_jmp ? 'b1 : (i_br ? result[0] : 'b0);
    assign o_tag      = i_tag;
    assign o_valid    = i_valid;

    // ALU
    always_comb begin
        case (i_alu_func)
            ALU_FUNC_ADD: result = i_src_a + i_src_b;
            ALU_FUNC_SUB: result = i_src_a - i_src_b;
            ALU_FUNC_AND: result = i_src_a & i_src_b;
            ALU_FUNC_OR:  result = i_src_a | i_src_b;
            ALU_FUNC_XOR: result = i_src_a ^ i_src_b;
            ALU_FUNC_SLL: result = i_src_a << i_shamt;
            ALU_FUNC_SRL: result = i_src_a >> i_shamt;
            ALU_FUNC_SRA: result = e_src_a >> i_shamt;
            ALU_FUNC_EQ:  result = i_src_a == i_src_b;
            ALU_FUNC_NE:  result = i_src_a != i_src_b;
            ALU_FUNC_LT:  result = s_src_a < s_src_b;
            ALU_FUNC_LTU: result = i_src_a < i_src_b;
            ALU_FUNC_GE:  result = s_src_a >= s_src_b;
            ALU_FUNC_GEU: result = i_src_a >= i_src_b;
            default:      result = 'b0;
        endcase
    end

endmodule