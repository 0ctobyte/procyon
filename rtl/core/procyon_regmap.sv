/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Register Map with tag information for register renaming

module procyon_regmap #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_REGMAP_DEPTH  = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5,

    parameter REGMAP_IDX_WIDTH   = $clog2(OPTN_REGMAP_DEPTH)
)(
    input  logic                           clk,
    input  logic                           n_rst,

    // FIXME: Temporary for simulation pass/fail detection
    output logic [OPTN_DATA_WIDTH-1:0]     o_sim_tp,

    // Flush signal -> Set all ready bits (basically invalidate tags)
    input  logic                           i_flush,

    // Destination register update interface
    input  logic                           i_regmap_retire_en,
    input  logic [OPTN_DATA_WIDTH-1:0]     i_regmap_retire_data,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]  i_regmap_retire_tag,
    input  logic [REGMAP_IDX_WIDTH-1:0]    i_regmap_retire_rdest,

    // Tag update interface
    input  logic                           i_regmap_rename_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]  i_regmap_rename_tag,
    input  logic [REGMAP_IDX_WIDTH-1:0]    i_regmap_rename_rdest,

    // Lookup source operand tag/data/rdy
    input  logic [REGMAP_IDX_WIDTH-1:0]    i_regmap_lookup_rsrc [0:1],
    output logic [OPTN_DATA_WIDTH-1:0]     o_regmap_lookup_data [0:1],
    output logic [OPTN_ROB_IDX_WIDTH-1:0]  o_regmap_lookup_tag  [0:1],
    output logic                           o_regmap_lookup_rdy  [0:1]
);

/* verilator lint_off UNUSED */
    logic [OPTN_REGMAP_DEPTH-1:0] regmap_retire_select;
    logic [OPTN_REGMAP_DEPTH-1:0] regmap_rename_select;
/* verilator lint_on  UNUSED */
    logic [OPTN_DATA_WIDTH-1:0] regmap_entry_data [0:OPTN_REGMAP_DEPTH-1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] regmap_entry_tag [0:OPTN_REGMAP_DEPTH-1];
    logic [OPTN_REGMAP_DEPTH-1:0] regmap_entry_rdy;

    // FIXME: Output this register for architectural simulation test pass/fail detection
    assign o_sim_tp = regmap_entry_data[4];

    genvar inst;
    generate
    for (inst = 1; inst < OPTN_REGMAP_DEPTH; inst++) begin : GEN_REGMAP_ENTRY_INST
        procyon_regmap_entry #(
            .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
            .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
        ) procyon_regmap_entry_inst (
            .clk(clk),
            .n_rst(n_rst),
            .i_flush(i_flush),
            .o_regmap_entry_data(regmap_entry_data[inst]),
            .o_regmap_entry_tag(regmap_entry_tag[inst]),
            .o_regmap_entry_rdy(regmap_entry_rdy[inst]),
            .i_regmap_retire_en(regmap_retire_select[inst]),
            .i_regmap_retire_data(i_regmap_retire_data),
            .i_regmap_retire_tag(i_regmap_retire_tag),
            .i_regmap_rename_en(regmap_rename_select[inst]),
            .i_regmap_rename_tag(i_regmap_rename_tag)
        );
    end
    endgenerate

    always_comb begin
        // The R0 register is always zero
        regmap_entry_data[0] = '0;
        regmap_entry_tag[0] = '0;
        regmap_entry_rdy[0] = 1'b1;
    end

    // Select vectors to enable writing to the registers whose select bit is set
    logic [OPTN_REGMAP_DEPTH-1:0] regmap_retire_vector;
    procyon_binary2onehot #(OPTN_REGMAP_DEPTH) regmap_retire_vector_binary2onehot (.i_binary(i_regmap_retire_rdest), .o_onehot(regmap_retire_vector));
    assign regmap_retire_select = {(OPTN_REGMAP_DEPTH){i_regmap_retire_en}} & regmap_retire_vector;

    logic [OPTN_REGMAP_DEPTH-1:0] regmap_rename_vector;
    procyon_binary2onehot #(OPTN_REGMAP_DEPTH) regmap_rename_vector_binary2onehot (.i_binary(i_regmap_rename_rdest), .o_onehot(regmap_rename_vector));
    assign regmap_rename_select = {(OPTN_REGMAP_DEPTH){i_regmap_rename_en}} & regmap_rename_vector;

    // We need to bypass data from the ROB retire interface when looking up mappings for source registers of the newly
    // dispatched instruction
    logic [OPTN_DATA_WIDTH-1:0] regmap_lookup_data [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] regmap_lookup_tag [0:1];
    logic regmap_lookup_rdy [0:1];

    always_comb begin
        for (int i = 0; i < 2; i++) begin
            logic lookup_bypass;
            logic [REGMAP_IDX_WIDTH-1:0] src;

            src = i_regmap_lookup_rsrc[i];

            lookup_bypass = i_regmap_retire_en & ~regmap_entry_rdy[src] & (regmap_entry_tag[src] == i_regmap_retire_tag) & (i_regmap_retire_rdest == src);

            regmap_lookup_data[i] = lookup_bypass ? i_regmap_retire_data : regmap_entry_data[src];
            regmap_lookup_tag[i] = lookup_bypass ? i_regmap_retire_tag  : regmap_entry_tag[src];
            regmap_lookup_rdy[i] = lookup_bypass | regmap_entry_rdy[src];
        end
    end

    assign o_regmap_lookup_data = regmap_lookup_data;
    assign o_regmap_lookup_tag = regmap_lookup_tag;
    assign o_regmap_lookup_rdy = regmap_lookup_rdy;

endmodule
