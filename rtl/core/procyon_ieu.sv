/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Integer Execution Unit

/* verilator lint_off IMPORTSTAR */
import procyon_core_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_ieu #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                          clk,
    input  logic                          n_rst,

    input  logic                          i_flush,

    // Common Data Bus
    output logic                          o_cdb_en,
    output logic                          o_cdb_redirect,
    output logic [OPTN_DATA_WIDTH-1:0]    o_cdb_data,
    output logic [OPTN_ROB_IDX_WIDTH-1:0] o_cdb_tag,

    // Reservation station interface
    input  logic                          i_fu_valid,
    input  pcyn_op_t                      i_fu_op,
/* verilator lint_off UNUSED */
    input  pcyn_op_is_t                   i_fu_op_is,
    input  logic [OPTN_DATA_WIDTH-1:0]    i_fu_imm,
/* verilator lint_on  UNUSED */
    input  logic [OPTN_DATA_WIDTH-1:0]    i_fu_src [0:1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_fu_tag,
    output logic                          o_fu_stall
);

    assign o_fu_stall = 1'b0;

    logic cdb_en;
    assign cdb_en = ~i_flush & i_fu_valid;
    procyon_srff #(1) o_cdb_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(cdb_en), .i_reset(1'b0), .o_q(o_cdb_en));

    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_fu_tag), .o_q(o_cdb_tag));

    // ALU
    logic [OPTN_DATA_WIDTH-1:0] result;

    always_comb begin
        logic [OPTN_DATA_WIDTH*2-1:0] e_src;
        logic signed [OPTN_DATA_WIDTH-1:0] s_src [0:1];
        pcyn_op_shamt_t shamt;

        // Extended src[0] for arithmetic right shifts
        e_src = {{(OPTN_DATA_WIDTH){i_fu_src[0][OPTN_DATA_WIDTH-1]}}, i_fu_src[0]};

        // Signed src inputs
        s_src[0] = i_fu_src[0];
        s_src[1] = i_fu_src[1];

        // Shift amount
        shamt = i_fu_src[1][PCYN_OP_SHAMT_WIDTH-1:0];

        unique case (i_fu_op)
            PCYN_OP_ADD: result = i_fu_src[0] + i_fu_src[1];
            PCYN_OP_SUB: result = i_fu_src[0] - i_fu_src[1];
            PCYN_OP_AND: result = i_fu_src[0] & i_fu_src[1];
            PCYN_OP_OR:  result = i_fu_src[0] | i_fu_src[1];
            PCYN_OP_XOR: result = i_fu_src[0] ^ i_fu_src[1];
            PCYN_OP_SLL: result = i_fu_src[0] << shamt;
            PCYN_OP_SRL: result = i_fu_src[0] >> shamt;
/* verilator lint_off WIDTH */
            PCYN_OP_SRA: result = OPTN_DATA_WIDTH'(e_src >> shamt);
            PCYN_OP_EQ:  result = i_fu_src[0] == i_fu_src[1];
            PCYN_OP_NE:  result = i_fu_src[0] != i_fu_src[1];
            PCYN_OP_LT:  result = s_src[0] < s_src[1];
            PCYN_OP_LTU: result = i_fu_src[0] < i_fu_src[1];
            PCYN_OP_GE:  result = s_src[0] >= s_src[1];
            PCYN_OP_GEU: result = i_fu_src[0] >= i_fu_src[1];
/* verilator lint_on  WIDTH */
            default:     result = '0;
        endcase
    end

    procyon_ff #(OPTN_DATA_WIDTH) o_data_ff (.clk(clk), .i_en(1'b1), .i_d(result), .o_q(o_cdb_data));

    logic redirect;
    assign redirect = i_fu_op_is[PCYN_OP_IS_JL_IDX] | (i_fu_op_is[PCYN_OP_IS_BR_IDX] & result[0]);
    procyon_ff #(1) o_redirect_ff (.clk(clk), .i_en(1'b1), .i_d(redirect), .o_q(o_cdb_redirect));

endmodule
