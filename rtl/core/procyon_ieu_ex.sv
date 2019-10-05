/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Integer Execution Unit - Execution Stage

`include "procyon_constants.svh"

module procyon_ieu_ex #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                             clk,
    input  logic                             n_rst,

    input  logic                             i_flush,

    input  logic [`PCYN_ALU_FUNC_WIDTH-1:0]  i_alu_func,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_src_a,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_src_b,
    input  logic [OPTN_ADDR_WIDTH-1:0]       i_iaddr,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_imm_b,
    input  logic [`PCYN_ALU_SHAMT_WIDTH-1:0] i_shamt,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]    i_tag,
    input  logic                             i_jmp,
    input  logic                             i_br,
    input  logic                             i_valid,

    output logic [OPTN_DATA_WIDTH-1:0]       o_data,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_addr,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]    o_tag,
    output logic                             o_redirect,
    output logic                             o_valid
);

    logic valid;
    assign valid = ~i_flush & i_valid;
    procyon_srff #(1) o_valid_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(valid), .i_reset(1'b0), .o_q(o_valid));

    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_tag), .o_q(o_tag));

    // ALU
    logic [OPTN_DATA_WIDTH-1:0] result;

    always_comb begin
        logic [OPTN_DATA_WIDTH*2-1:0] e_src_a;
        logic signed [OPTN_DATA_WIDTH-1:0] s_src_a;
        logic signed [OPTN_DATA_WIDTH-1:0] s_src_b;

        // Extended src_a for arithmetic right shifts
        e_src_a = {{(OPTN_DATA_WIDTH){i_src_a[OPTN_DATA_WIDTH-1]}}, i_src_a};

        // Signed src inputs
        s_src_a = i_src_a;
        s_src_b = i_src_b;

        case (i_alu_func)
            `PCYN_ALU_FUNC_ADD: result = i_src_a + i_src_b;
            `PCYN_ALU_FUNC_SUB: result = i_src_a - i_src_b;
            `PCYN_ALU_FUNC_AND: result = i_src_a & i_src_b;
            `PCYN_ALU_FUNC_OR:  result = i_src_a | i_src_b;
            `PCYN_ALU_FUNC_XOR: result = i_src_a ^ i_src_b;
            `PCYN_ALU_FUNC_SLL: result = i_src_a << i_shamt;
            `PCYN_ALU_FUNC_SRL: result = i_src_a >> i_shamt;
/* verilator lint_off WIDTH */
            `PCYN_ALU_FUNC_SRA: result = OPTN_DATA_WIDTH'(e_src_a >> i_shamt);
            `PCYN_ALU_FUNC_EQ:  result = i_src_a == i_src_b;
            `PCYN_ALU_FUNC_NE:  result = i_src_a != i_src_b;
            `PCYN_ALU_FUNC_LT:  result = s_src_a < s_src_b;
            `PCYN_ALU_FUNC_LTU: result = i_src_a < i_src_b;
            `PCYN_ALU_FUNC_GE:  result = s_src_a >= s_src_b;
            `PCYN_ALU_FUNC_GEU: result = i_src_a >= i_src_b;
/* verilator lint_on  WIDTH */
            default:            result = '0;
        endcase
    end

    logic [OPTN_DATA_WIDTH-1:0] data;
    assign data = i_jmp ? i_iaddr + 4 : result;
    procyon_ff #(OPTN_DATA_WIDTH) o_data_ff (.clk(clk), .i_en(1'b1), .i_d(data), .o_q(o_data));

    logic [OPTN_ADDR_WIDTH-1:0] addr;
    assign addr = i_jmp ? result : i_iaddr + i_imm_b;
    procyon_ff #(OPTN_ADDR_WIDTH) o_addr_ff (.clk(clk), .i_en(1'b1), .i_d(addr), .o_q(o_addr));

    logic redirect;
    assign redirect = i_jmp | (i_br & result[0]);
    procyon_ff #(1) o_redirect_ff (.clk(clk), .i_en(1'b1), .i_d(redirect), .o_q(o_redirect));

endmodule
