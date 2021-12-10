/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Reservation Station switch
// Routes reservation station enqueue signals to the right reservation station
// Also bypasses source data from CDB on enqueue cycle

module procyon_rs_switch
    import procyon_lib_pkg::*, procyon_core_pkg::*;
#(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5,
    parameter OPTN_CDB_DEPTH     = 2
)(
    input  logic                          clk,
    input  logic                          n_rst,

    input  logic                          i_cdb_en [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_cdb_data [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_cdb_tag [0:OPTN_CDB_DEPTH-1],

    input  pcyn_rs_fu_type_t              i_rs_fu_type [0:OPTN_CDB_DEPTH-1],

    input  logic                          i_rs_reserve_en,
/* verilator lint_off UNUSED */
    input  pcyn_op_is_t                   i_rs_reserve_op_is,
/* verilator lint_on  UNUSED */
    output logic [OPTN_CDB_DEPTH-1:0]     o_rs_reserve_en,

    input  logic                          i_rs_src_rdy [0:1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_rs_src_data [0:1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_rs_src_tag [0:1],
    output logic                          o_rs_src_rdy [0:1],
    output logic [OPTN_DATA_WIDTH-1:0]    o_rs_src_data [0:1],
    output logic [OPTN_ROB_IDX_WIDTH-1:0] o_rs_src_tag [0:1],

    input  logic [OPTN_CDB_DEPTH-1:0]     i_rs_stall,
    output logic                          o_rs_stall
);

    localparam CDB_IDX_WIDTH = `PCYN_C2I(OPTN_CDB_DEPTH);

    // Transpose the i_rs_fu_type array to allow indexing the array by FU type rather then RS #. This way we'll
    // get a sequence of bits, one for each RS, indicating if that FU type is attached to that RS.
    logic [OPTN_CDB_DEPTH-1:0] rs_fu_type [PCYN_RS_FU_TYPE_WIDTH-1:0];

    always_comb begin
        for (int i = 0; i < PCYN_RS_FU_TYPE_WIDTH; i++) begin
            for (int j = 0; j < OPTN_CDB_DEPTH; j++) begin
                rs_fu_type[i][j] = i_rs_fu_type[j][i];
            end
        end
    end

    // Figure out what kind of RS this op needs to be sent to
    logic [PCYN_RS_FU_TYPE_IDX_WIDTH-1:0] rs_fu_type_idx;
    assign rs_fu_type_idx = (i_rs_reserve_op_is[PCYN_OP_IS_ST_IDX] | i_rs_reserve_op_is[PCYN_OP_IS_LD_IDX]) ? PCYN_RS_FU_TYPE_IDX_LSU : PCYN_RS_FU_TYPE_IDX_IEU;

    // Get a vector of RS's that support this type of op
    logic [OPTN_CDB_DEPTH-1:0] rs_supported;
    assign rs_supported = rs_fu_type[rs_fu_type_idx];

    // Round robin arbitration to select one RS that supports this op
    logic [OPTN_CDB_DEPTH-1:0] rs_granted;
    procyon_rr_picker #(OPTN_CDB_DEPTH) rs_granted_rr_picker (.clk(clk), .n_rst(n_rst), .i_valid(i_rs_reserve_en), .i_requests(rs_supported), .o_grant(rs_granted));

    // Output reserve signals to reservation stations
    assign o_rs_reserve_en = i_rs_reserve_en ? rs_granted : '0;
    assign o_rs_stall = |(rs_granted & i_rs_stall);

    // Check if we need to bypass source data from the CDB when enqueuing new instruction in the Reservation Stations
    logic rs_src_rdy_mux [0:1];
    logic [OPTN_DATA_WIDTH-1:0] rs_src_data_mux [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] rs_src_tag_mux [0:1];

    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            rs_src_rdy_mux[src_idx] = i_rs_src_rdy[src_idx];
            rs_src_data_mux[src_idx] = '0;
            rs_src_tag_mux[src_idx]  = i_rs_src_tag[src_idx];

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                logic cdb_tag_match;
                cdb_tag_match = i_cdb_en[cdb_idx] & (i_cdb_tag[cdb_idx] == i_rs_src_tag[src_idx]);

                rs_src_rdy_mux[src_idx] = cdb_tag_match | rs_src_rdy_mux[src_idx];
                rs_src_data_mux[src_idx] = cdb_tag_match ? i_cdb_data[cdb_idx] : rs_src_data_mux[src_idx];
                rs_src_tag_mux[src_idx]  = cdb_tag_match ? i_cdb_tag[cdb_idx] : rs_src_tag_mux[src_idx];
            end

            rs_src_data_mux[src_idx] = i_rs_src_rdy[src_idx] ? i_rs_src_data[src_idx] : rs_src_data_mux[src_idx];
        end
    end

    assign o_rs_src_rdy = rs_src_rdy_mux;
    assign o_rs_src_data = rs_src_data_mux;
    assign o_rs_src_tag = rs_src_tag_mux;

endmodule
