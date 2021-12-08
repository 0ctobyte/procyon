/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Register Alias Table with tag information for register renaming

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_rat #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_RAT_DEPTH     = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                                 clk,
    input  logic                                 n_rst,

    // FIXME: Temporary for simulation pass/fail detection
    output logic [OPTN_DATA_WIDTH-1:0]           o_sim_tp,

    // Flush signal -> Set all ready bits (basically invalidate tags)
    input  logic                                 i_flush,

    // Lookup source operand tag/data/rdy
    input  logic [`PCYN_C2I(OPTN_RAT_DEPTH)-1:0] i_rat_lookup_rsrc [0:1],
    output logic                                 o_rat_lookup_rdy [0:1],
    output logic [OPTN_DATA_WIDTH-1:0]           o_rat_lookup_data [0:1],
    output logic [OPTN_ROB_IDX_WIDTH-1:0]        o_rat_lookup_tag [0:1],

    // Tag update interface
    input  logic                                 i_rat_rename_en,
    input  logic [`PCYN_C2I(OPTN_RAT_DEPTH)-1:0] i_rat_rename_rdst,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]        i_rat_rename_tag,

    // Destination register update interface
    input  logic                                 i_rat_retire_en,
    input  logic [`PCYN_C2I(OPTN_RAT_DEPTH)-1:0] i_rat_retire_rdst,
    input  logic [OPTN_DATA_WIDTH-1:0]           i_rat_retire_data,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]        i_rat_retire_tag
);

    localparam RAT_IDX_WIDTH = `PCYN_C2I(OPTN_RAT_DEPTH);

/* verilator lint_off UNUSED */
    logic [OPTN_RAT_DEPTH-1:0] rat_retire_select;
    logic [OPTN_RAT_DEPTH-1:0] rat_rename_select;
/* verilator lint_on  UNUSED */
    logic [OPTN_DATA_WIDTH-1:0] rat_entry_data [0:OPTN_RAT_DEPTH-1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] rat_entry_tag [0:OPTN_RAT_DEPTH-1];
    logic [OPTN_RAT_DEPTH-1:0] rat_entry_rdy;

    // FIXME: Output this register for architectural simulation test pass/fail detection
    assign o_sim_tp = rat_entry_data[4];

    genvar inst;
    generate
    for (inst = 1; inst < OPTN_RAT_DEPTH; inst++) begin : GEN_RAT_ENTRY_INST
        procyon_rat_entry #(
            .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
            .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
        ) procyon_rat_entry_inst (
            .clk(clk),
            .n_rst(n_rst),
            .i_flush(i_flush),
            .o_rat_entry_data(rat_entry_data[inst]),
            .o_rat_entry_tag(rat_entry_tag[inst]),
            .o_rat_entry_rdy(rat_entry_rdy[inst]),
            .i_rat_retire_en(rat_retire_select[inst]),
            .i_rat_retire_data(i_rat_retire_data),
            .i_rat_retire_tag(i_rat_retire_tag),
            .i_rat_rename_en(rat_rename_select[inst]),
            .i_rat_rename_tag(i_rat_rename_tag)
        );
    end
    endgenerate

    always_comb begin
        // The R0 register is always zero
        rat_entry_data[0] = '0;
        rat_entry_tag[0] = '0;
        rat_entry_rdy[0] = 1'b1;
    end

    // Select vectors to enable writing to the registers whose select bit is set
    logic [OPTN_RAT_DEPTH-1:0] rat_retire_vector;
    procyon_binary2onehot #(OPTN_RAT_DEPTH) rat_retire_vector_binary2onehot (.i_binary(i_rat_retire_rdst), .o_onehot(rat_retire_vector));
    assign rat_retire_select = {(OPTN_RAT_DEPTH){i_rat_retire_en}} & rat_retire_vector;

    logic [OPTN_RAT_DEPTH-1:0] rat_rename_vector;
    procyon_binary2onehot #(OPTN_RAT_DEPTH) rat_rename_vector_binary2onehot (.i_binary(i_rat_rename_rdst), .o_onehot(rat_rename_vector));
    assign rat_rename_select = {(OPTN_RAT_DEPTH){i_rat_rename_en}} & rat_rename_vector;

    // Lookup source readiness, data and ROB tag mappings in the register alias table. The tags are forwared to the ROB so it
    // can lookup ready data or bypass from the CDBs. Make sure to bypass data from retiring instructions in the same cycle.
    logic rat_lookup_rdy [0:1];
    logic [OPTN_DATA_WIDTH-1:0] rat_lookup_data [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] rat_lookup_tag [0:1];

    always_comb begin
        for (int i = 0; i < 2; i++) begin
            logic lookup_bypass;
            logic [RAT_IDX_WIDTH-1:0] src;

            src = i_rat_lookup_rsrc[i];
            lookup_bypass = i_rat_retire_en & ~rat_entry_rdy[src] & (rat_entry_tag[src] == i_rat_retire_tag) & (i_rat_retire_rdst == src);

            rat_lookup_rdy[i] = lookup_bypass | rat_entry_rdy[src];
            rat_lookup_data[i] = lookup_bypass ? i_rat_retire_data : rat_entry_data[src];
            rat_lookup_tag[i] = rat_entry_tag[src];
        end
    end

    assign o_rat_lookup_rdy = rat_lookup_rdy;
    assign o_rat_lookup_data = rat_lookup_data;
    assign o_rat_lookup_tag = rat_lookup_tag;

endmodule
