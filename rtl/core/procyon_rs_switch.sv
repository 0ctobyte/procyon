/*
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Reservation Station switch
// Routes reservation station enqueue signals to the right reservation station
// Also bypasses source data from CDB on enqueue cycle

`include "procyon_constants.svh"

module procyon_rs_switch #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5,
    parameter OPTN_CDB_DEPTH     = 2
)(
    input  logic                          i_cdb_en      [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_cdb_data    [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_cdb_tag     [0:OPTN_CDB_DEPTH-1],

    input  logic                          i_rs_en,
    input  logic [`PCYN_OPCODE_WIDTH-1:0] i_rs_opcode,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_rs_src_tag  [0:1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_rs_src_data [0:1],
    input  logic                          i_rs_src_rdy  [0:1],
    output logic                          o_rs_en       [0:OPTN_CDB_DEPTH-1],
    output logic [OPTN_ROB_IDX_WIDTH-1:0] o_rs_src_tag  [0:1],
    output logic [OPTN_DATA_WIDTH-1:0]    o_rs_src_data [0:1],
    output logic                          o_rs_src_rdy  [0:1],

    input  logic                          i_rs_stall    [0:OPTN_CDB_DEPTH-1],
    output logic                          o_rs_stall
);

    logic                          rs_opcode_is_lsu;
    logic [1:0]                    cdb_rs_bypass    [0:OPTN_CDB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]    rs_src_data      [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] rs_src_tag       [0:1];
    logic                          rs_src_rdy       [0:1];

    assign rs_opcode_is_lsu  = (i_rs_opcode == `PCYN_OPCODE_STORE) | (i_rs_opcode == `PCYN_OPCODE_LOAD);
    assign o_rs_en           = '{~rs_opcode_is_lsu ? i_rs_en : 1'b0, rs_opcode_is_lsu ?  i_rs_en : 1'b0};
    assign o_rs_stall        = rs_opcode_is_lsu ? i_rs_stall[1] : i_rs_stall[0];
    assign o_rs_src_tag      = rs_src_tag;
    assign o_rs_src_data     = rs_src_data;
    assign o_rs_src_rdy      = rs_src_rdy;

    // Check if we need to bypass source data from the CDB when enqueuing new instruction in the Reservation Stations
    always_comb begin
        for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                cdb_rs_bypass[cdb_idx][src_idx] = i_cdb_en[cdb_idx] & (i_cdb_tag[cdb_idx] == i_rs_src_tag[src_idx]);
            end
        end
    end

    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            rs_src_rdy[src_idx] = i_rs_src_rdy[src_idx];

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                rs_src_rdy[src_idx] = cdb_rs_bypass[cdb_idx][src_idx] | rs_src_rdy[src_idx];
            end
        end
    end

    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            rs_src_data[src_idx] = {(OPTN_DATA_WIDTH){1'b0}};
            rs_src_tag[src_idx]  = i_rs_src_tag[src_idx];

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                if (cdb_rs_bypass[cdb_idx][src_idx]) begin
                    rs_src_data[src_idx] = i_cdb_data[cdb_idx];
                    rs_src_tag[src_idx]  = i_cdb_tag[cdb_idx];
                end
            end

            rs_src_data[src_idx] = i_rs_src_rdy[src_idx] ? i_rs_src_data[src_idx] : rs_src_data[src_idx];
        end
    end

endmodule
