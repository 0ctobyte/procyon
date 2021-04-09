/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

`include "procyon_constants.svh"

module procyon_rs_entry #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5,
    parameter OPTN_CDB_DEPTH     = 2,
    parameter OPTN_RS_DEPTH      = 16,

    parameter RS_IDX_WIDTH       = $clog2(OPTN_RS_DEPTH)
)(
    input  logic                          clk,
    input  logic                          n_rst,

    input  logic                          i_flush,

    output logic                          o_ready,

    output logic                          o_rs_entry_empty,
    output logic [RS_IDX_WIDTH-1:0]       o_rs_entry_age,
    output logic [`PCYN_OPCODE_WIDTH-1:0] o_rs_entry_opcode,
    output logic [OPTN_ADDR_WIDTH-1:0]    o_rs_entry_iaddr,
    output logic [OPTN_DATA_WIDTH-1:0]    o_rs_entry_insn,
    output logic [OPTN_DATA_WIDTH-1:0]    o_rs_entry_src_data [0:1],
    output logic [OPTN_ROB_IDX_WIDTH-1:0] o_rs_entry_tag,

    // Common Data Bus networks
    input  logic                          i_cdb_en            [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_cdb_data          [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_cdb_tag           [0:OPTN_CDB_DEPTH-1],

    // Dispatch interface
    input  logic                          i_dispatch_en,
    input  logic [`PCYN_OPCODE_WIDTH-1:0] i_dispatch_opcode,
    input  logic [OPTN_ADDR_WIDTH-1:0]    i_dispatch_iaddr,
    input  logic [OPTN_DATA_WIDTH-1:0]    i_dispatch_insn,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_dispatch_src_tag  [0:1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_dispatch_src_data [0:1],
    input  logic                          i_dispatch_src_rdy  [0:1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_dispatch_dst_tag,

    // Indication that this entry is going to be issued
    input  logic                          i_issue_en,

    // Used to calculate age updates for this entry
    input  logic                          i_dispatching,
    input  logic                          i_issuing,
    input  logic [RS_IDX_WIDTH-1:0]       i_rs_issue_entry_age
);

    // Reservation station entry registers
    // empty:         Indicates if this entry is currently empty
    // age:           Indicates the age of the entry compared to all other entries
    // opcode:        The opcode of the instruction stored in this entry
    // iaddr:         The instruction address (i.e. PC)
    // insn:          The actual instruction bits
    // src_rdy:       Two bits to indicate the ready status of each source operand
    // src_data:      Actual data for each of the two source operands
    // src_tag:       ROB entry number for each source this entry is waiting on data for
    // dst_tag:       The ROB entry number to write the data (if any) and status to when this op has finished executing
    logic rs_entry_empty_r;
    logic [RS_IDX_WIDTH-1:0] rs_entry_age_r;
    logic [`PCYN_OPCODE_WIDTH-1:0] rs_entry_opcode_r;
    logic [OPTN_ADDR_WIDTH-1:0] rs_entry_iaddr_r;
    logic [OPTN_DATA_WIDTH-1:0] rs_entry_insn_r;
    logic rs_entry_src_rdy_r [0:1];
    logic [OPTN_DATA_WIDTH-1:0] rs_entry_src_data_r [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] rs_entry_src_tag_r [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] rs_entry_dst_tag_r;

    // The empty bit is only cleared if the entry will be used to hold the next dispatched instruction.
    // Set it if the entry is issuing or on a pipeline flush
    logic rs_entry_empty_mux;

    always_comb begin
        logic [1:0] rs_entry_empty_sel;
        rs_entry_empty_sel = {i_issue_en, i_dispatch_en};

        case (rs_entry_empty_sel)
            2'b00: rs_entry_empty_mux = rs_entry_empty_r;
            2'b01: rs_entry_empty_mux = 1'b0;
            2'b10: rs_entry_empty_mux = 1'b1;
            2'b11: rs_entry_empty_mux = 1'b1;
        endcase

        rs_entry_empty_mux = i_flush | rs_entry_empty_mux;
    end

    procyon_srff #(1) rs_entry_empty_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(rs_entry_empty_mux), .i_reset(1'b1), .o_q(rs_entry_empty_r));

    // Update entry for newly dispatched instruction
    procyon_ff #(`PCYN_OPCODE_WIDTH) rs_entry_opcode_r_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(i_dispatch_opcode), .o_q(rs_entry_opcode_r));
    procyon_ff #(OPTN_ADDR_WIDTH) rs_entry_iaddr_r_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(i_dispatch_iaddr), .o_q(rs_entry_iaddr_r));
    procyon_ff #(OPTN_DATA_WIDTH) rs_entry_insn_r_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(i_dispatch_insn), .o_q(rs_entry_insn_r));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) rs_entry_src_tag_r_0_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(i_dispatch_src_tag[0]), .o_q(rs_entry_src_tag_r[0]));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) rs_entry_src_tag_r_1_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(i_dispatch_src_tag[1]), .o_q(rs_entry_src_tag_r[1]));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) rs_entry_dst_tag_r_ff (.clk(clk), .i_en(i_dispatch_en), .i_d(i_dispatch_dst_tag), .o_q(rs_entry_dst_tag_r));

    // Grab data from the CDB for the source operands and set the ready bits to true. Don't mess with the src data if
    // it's already "ready", regardless of what is being broadcast on the CDB! This really only applies to ops that use
    // X0 register since the src tag for the X0 register is always 0 which could possibly be a valid tag. Priority mux
    // to select input from the CDB busses, where the higher "numbered" CDB bus gets priority Of course, this shouldn't
    // matter since the CDBs should never broadcast the same tag on the same cycle
    logic [OPTN_DATA_WIDTH-1:0] rs_entry_src_data_mux [0:1];
    logic rs_entry_src_rdy_mux [0:1];

    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            rs_entry_src_data_mux[src_idx] = rs_entry_src_data_r[src_idx];
            rs_entry_src_rdy_mux[src_idx] = rs_entry_src_rdy_r[src_idx];

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                // Check both source tags for each RS entry to see if a CDB is broadcasting a matching tag
                logic cdb_tag_match;
                cdb_tag_match = i_cdb_en[cdb_idx] & (i_cdb_tag[cdb_idx] == rs_entry_src_tag_r[src_idx]);

                rs_entry_src_data_mux[src_idx] = (~rs_entry_src_rdy_r[src_idx] & cdb_tag_match) ? i_cdb_data[cdb_idx] : rs_entry_src_data_mux[src_idx];

                // An entry's sources are ready if it's been previously marked ready or if any of the CDB busses
                // broadcast a matching tag that the source is waiting on.
                rs_entry_src_rdy_mux[src_idx] = cdb_tag_match | rs_entry_src_rdy_mux[src_idx];
            end
        end

        // Take the dispatch data and rdy bits if we're using this entry to enqueue a new op
        rs_entry_src_data_mux = i_dispatch_en ? i_dispatch_src_data : rs_entry_src_data_mux;
        rs_entry_src_rdy_mux = i_dispatch_en ? i_dispatch_src_rdy : rs_entry_src_rdy_mux;
    end

    procyon_ff #(OPTN_DATA_WIDTH) rs_entry_src_data_r_0_ff (.clk(clk), .i_en(1'b1), .i_d(rs_entry_src_data_mux[0]), .o_q(rs_entry_src_data_r[0]));
    procyon_ff #(OPTN_DATA_WIDTH) rs_entry_src_data_r_1_ff (.clk(clk), .i_en(1'b1), .i_d(rs_entry_src_data_mux[1]), .o_q(rs_entry_src_data_r[1]));
    procyon_ff #(1) rs_entry_src_rdy_r_0_ff (.clk(clk), .i_en(1'b1), .i_d(rs_entry_src_rdy_mux[0]), .o_q(rs_entry_src_rdy_r[0]));
    procyon_ff #(1) rs_entry_src_rdy_r_1_ff (.clk(clk), .i_en(1'b1), .i_d(rs_entry_src_rdy_mux[1]), .o_q(rs_entry_src_rdy_r[1]));

    // An entry's age needs to be adjusted each time an instruction is issued or dispatched. If a new instruction is
    // dispatched only, it starts off with an age of 0 and all other entries' age are incremented. If an instruction is
    // only issued then only the entries that have an age greater than the issuing entry's age will be decremented.
    // If an instruction is being dispatched and another instruction is being issued in the same cycle, then we only
    // increment those entries that have an age less than the issuing entry's age.
    logic [RS_IDX_WIDTH-1:0] rs_entry_age_mux;

    always_comb begin
        case ({i_dispatching, i_issuing})
            2'b00: rs_entry_age_mux = rs_entry_age_r;
            2'b01: rs_entry_age_mux = rs_entry_age_r - (RS_IDX_WIDTH)'((rs_entry_age_r > i_rs_issue_entry_age) ? 1 : 0);
            2'b10: rs_entry_age_mux = i_dispatch_en ? '0 : (rs_entry_age_r + (RS_IDX_WIDTH)'(1));
            2'b11: rs_entry_age_mux = i_dispatch_en ? '0 : (rs_entry_age_r + (RS_IDX_WIDTH)'((rs_entry_age_r < i_rs_issue_entry_age) ? 1 : 0));
        endcase
    end

    procyon_ff #(RS_IDX_WIDTH) rs_entry_age_ff (.clk(clk), .i_en(1'b1), .i_d(rs_entry_age_mux), .o_q(rs_entry_age_r));

    // An entry is ready to issue if it is not empty and has both it's source operands
    assign o_ready = ~rs_entry_empty_r & rs_entry_src_rdy_r[0] & rs_entry_src_rdy_r[1];

    // Output entry signals
    assign o_rs_entry_empty = rs_entry_empty_r;
    assign o_rs_entry_age = rs_entry_age_r;
    assign o_rs_entry_opcode = rs_entry_opcode_r;
    assign o_rs_entry_iaddr = rs_entry_iaddr_r;
    assign o_rs_entry_insn = rs_entry_insn_r;
    assign o_rs_entry_src_data = rs_entry_src_data_r;
    assign o_rs_entry_tag = rs_entry_dst_tag_r;

endmodule