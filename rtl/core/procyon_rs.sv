/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Reservation Station with age-matrix based out of order issue
// The reservation station will pick the oldest instruction that has all it's source operands ready for issue.
// New instructions allocated in the reservation station will be assigned an age of 0 which will increment/decrement
// if other instructions are dispatched/issued. The reservation station will also listen in on all CDB busses and pick
// up source data for both sources if the CDBs broadcast matching tags that the source is waiting on

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
import procyon_core_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_rs #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5,
    parameter OPTN_CDB_DEPTH     = 2,
    parameter OPTN_RS_DEPTH      = 16,
    parameter OPTN_RS_FU_TYPE    = 0
)(
    input  logic                          clk,
    input  logic                          n_rst,

    input  logic                          i_flush,

    // One-hot vector indicating what functional unit is attached to this reservation station
    output pcyn_rs_fu_type_t              o_rs_fu_type,

    // Common Data Bus networks
    input  logic                          i_cdb_en [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_cdb_data [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_cdb_tag [0:OPTN_CDB_DEPTH-1],

    // Dispatch interface
    input  logic                          i_rs_reserve_en,
    input  pcyn_op_t                      i_rs_dispatch_op,
    input  pcyn_op_is_t                   i_rs_dispatch_op_is,
    input  logic [OPTN_DATA_WIDTH-1:0]    i_rs_dispatch_imm,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_rs_dispatch_dst_tag,
    input  logic                          i_rs_dispatch_src_rdy [0:1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_rs_dispatch_src_data [0:1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_rs_dispatch_src_tag [0:1],
    output logic                          o_rs_stall,

    // Functional Unit interface
    input  logic                          i_fu_stall,
    output logic                          o_fu_valid,
    output pcyn_op_t                      o_fu_op,
    output pcyn_op_is_t                   o_fu_op_is,
    output logic [OPTN_DATA_WIDTH-1:0]    o_fu_imm,
    output logic [OPTN_DATA_WIDTH-1:0]    o_fu_src [0:1],
    output logic [OPTN_ROB_IDX_WIDTH-1:0] o_fu_tag
);

    localparam RS_IDX_WIDTH = `PCYN_C2I(OPTN_RS_DEPTH);

    assign o_rs_fu_type = pcyn_rs_fu_type_t'(OPTN_RS_FU_TYPE);

    logic [OPTN_RS_DEPTH-1:0] rs_entry_ready;
    logic [OPTN_RS_DEPTH-1:0] rs_entry_empty;
    logic [RS_IDX_WIDTH-1:0] rs_entry_age [0:OPTN_RS_DEPTH-1];
    pcyn_op_t rs_entry_op [0:OPTN_RS_DEPTH-1];
    pcyn_op_is_t rs_entry_op_is [0:OPTN_RS_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0] rs_entry_imm [0:OPTN_RS_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0] rs_entry_src_data [0:OPTN_RS_DEPTH-1] [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] rs_entry_tag [0:OPTN_RS_DEPTH-1];
    logic [OPTN_RS_DEPTH-1:0] rs_reserve_select;
    logic [OPTN_RS_DEPTH-1:0] rs_dispatch_select_r;
    logic [OPTN_RS_DEPTH-1:0] rs_issue_select;
    logic dispatching;
    logic issuing;
    logic [RS_IDX_WIDTH-1:0] rs_issue_entry;

    genvar inst;
    generate
    for (inst = 0; inst < OPTN_RS_DEPTH; inst++) begin : GEN_RS_ENTRY_INST
        procyon_rs_entry #(
            .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
            .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
            .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH),
            .OPTN_CDB_DEPTH(OPTN_CDB_DEPTH),
            .OPTN_RS_DEPTH(OPTN_RS_DEPTH)
        ) procyon_rs_entry_inst (
            .clk(clk),
            .n_rst(n_rst),
            .i_flush(i_flush),
            .o_ready(rs_entry_ready[inst]),
            .o_rs_entry_empty(rs_entry_empty[inst]),
            .o_rs_entry_age(rs_entry_age[inst]),
            .o_rs_entry_op(rs_entry_op[inst]),
            .o_rs_entry_op_is(rs_entry_op_is[inst]),
            .o_rs_entry_imm(rs_entry_imm[inst]),
            .o_rs_entry_src_data(rs_entry_src_data[inst]),
            .o_rs_entry_tag(rs_entry_tag[inst]),
            .i_cdb_en(i_cdb_en),
            .i_cdb_data(i_cdb_data),
            .i_cdb_tag(i_cdb_tag),
            .i_reserve_en(rs_reserve_select[inst]),
            .i_dispatch_en(rs_dispatch_select_r[inst]),
            .i_dispatch_op(i_rs_dispatch_op),
            .i_dispatch_op_is(i_rs_dispatch_op_is),
            .i_dispatch_imm(i_rs_dispatch_imm),
            .i_dispatch_dst_tag(i_rs_dispatch_dst_tag),
            .i_dispatch_src_rdy(i_rs_dispatch_src_rdy),
            .i_dispatch_src_data(i_rs_dispatch_src_data),
            .i_dispatch_src_tag(i_rs_dispatch_src_tag),
            .i_issue_en(rs_issue_select[inst]),
            .i_dispatching(dispatching),
            .i_issuing(issuing),
            .i_rs_issue_entry_age(rs_entry_age[rs_issue_entry])
        );
    end
    endgenerate

    // Generate a one-hot vector reserving an RS entry for the next cycle when the dispatcher will enqueue into the entry
    logic [OPTN_RS_DEPTH-1:0] rs_reserve_picked;
    procyon_priority_picker #(OPTN_RS_DEPTH) rs_reserve_picked_priority_picker (.i_in(rs_entry_empty), .o_pick(rs_reserve_picked));
    assign rs_reserve_select = {(OPTN_RS_DEPTH){i_rs_reserve_en}} & rs_reserve_picked;

    procyon_ff #(OPTN_RS_DEPTH) rs_dispatch_select_r_ff (.clk(clk), .i_en(1'b1), .i_d(rs_reserve_select), .o_q(rs_dispatch_select_r));

    logic n_fu_stall;
    assign n_fu_stall = ~i_fu_stall;

    logic [OPTN_RS_DEPTH-1:0] rs_entry_oldest;

    always_comb begin
        logic [OPTN_RS_DEPTH-1:0] rs_age_matrix [0:OPTN_RS_DEPTH-1];
        logic [OPTN_RS_DEPTH-1:0] n_rs_entry_ready;

        n_rs_entry_ready = ~rs_entry_ready;

        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            // Generate the age matrix. A reservation station entry's age must be greater than all other reservation
            // station entries that are also ready to issue
            for (int j = 0; j < OPTN_RS_DEPTH; j++) begin
                if (i == j) rs_age_matrix[i][j] = 1'b1;
                else        rs_age_matrix[i][j] = rs_entry_age[i] > rs_entry_age[j];
            end

            // The OR with the complement of the rs_entry_ready vector is to discard age comparisons with entries that
            // aren't ready to issue
            rs_entry_oldest[i] = n_fu_stall & (&(rs_age_matrix[i] | n_rs_entry_ready));
        end

    end

    // Generate a one-hot vector of the oldest entry ready to issue
    assign rs_issue_select = rs_entry_oldest & rs_entry_ready;

    // Convert one-hot issue_select vector to binary RS entry #
    procyon_onehot2binary #(OPTN_RS_DEPTH) rs_issue_entry_onehot2binary (.i_onehot(rs_issue_select), .o_binary(rs_issue_entry));

    logic rs_full;
    assign rs_full = (rs_entry_empty == 0);

    assign dispatching = (rs_dispatch_select_r != 0);
    assign issuing = (rs_issue_select != 0);

    // The reservation station is full if there are no empty entries. Assert the stall signal in this situation
    assign o_rs_stall = rs_full;

    // Assign functional unit output
    logic fu_valid_r;
    logic fu_valid;

    assign fu_valid = i_fu_stall ? fu_valid_r : (~i_flush & issuing);
    procyon_srff #(1) fu_valid_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fu_valid), .i_reset(1'b0), .o_q(fu_valid_r));

    assign o_fu_valid = fu_valid_r;

    procyon_ff #(PCYN_OP_WIDTH) o_fu_op_ff (.clk(clk), .i_en(n_fu_stall), .i_d(rs_entry_op[rs_issue_entry]), .o_q(o_fu_op));
    procyon_ff #(PCYN_OP_IS_WIDTH) o_fu_op_is_ff (.clk(clk), .i_en(n_fu_stall), .i_d(rs_entry_op_is[rs_issue_entry]), .o_q(o_fu_op_is));
    procyon_ff #(OPTN_DATA_WIDTH) o_fu_imm_ff (.clk(clk), .i_en(n_fu_stall), .i_d(rs_entry_imm[rs_issue_entry]), .o_q(o_fu_imm));
    procyon_ff #(OPTN_DATA_WIDTH) o_fu_src_0_ff (.clk(clk), .i_en(n_fu_stall), .i_d(rs_entry_src_data[rs_issue_entry][0]), .o_q(o_fu_src[0]));
    procyon_ff #(OPTN_DATA_WIDTH) o_fu_src_1_ff (.clk(clk), .i_en(n_fu_stall), .i_d(rs_entry_src_data[rs_issue_entry][1]), .o_q(o_fu_src[1]));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_fu_tag_ff (.clk(clk), .i_en(n_fu_stall), .i_d(rs_entry_tag[rs_issue_entry]), .o_q(o_fu_tag));

endmodule
