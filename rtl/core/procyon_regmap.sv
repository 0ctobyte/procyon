/*
 * Copyright (c) 2019 Sekhar Bhattacharya
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
    input  logic [OPTN_DATA_WIDTH-1:0]     i_regmap_retire_data,
    input  logic [REGMAP_IDX_WIDTH-1:0]    i_regmap_retire_rdest,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]  i_regmap_retire_tag,
    input  logic                           i_regmap_retire_en,

    // Tag update interface
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]  i_regmap_rename_tag,
    input  logic [REGMAP_IDX_WIDTH-1:0]    i_regmap_rename_rdest,
    input  logic                           i_regmap_rename_en,

    // Lookup source operand tag/data/rdy
    input  logic                           i_regmap_lookup_valid,
    input  logic [REGMAP_IDX_WIDTH-1:0]    i_regmap_lookup_rsrc [0:1],
    output logic                           o_regmap_lookup_rdy  [0:1],
    output logic [OPTN_ROB_IDX_WIDTH-1:0]  o_regmap_lookup_tag  [0:1],
    output logic [OPTN_DATA_WIDTH-1:0]     o_regmap_lookup_data [0:1]
);

    // Each Register Map entry will have a data value, tag and ready bit
    // The data value is updated when the ROB writes back to the destination register of a retired instruction
    // The tag is updated for the destination register whenever the ROB enqueues a new instruction
    // The ready bit is set when the ROB retires and writes back to that register or cleared when the instruction is enqueued in the ROB
    logic [OPTN_DATA_WIDTH-1:0]    regmap_data_q      [0:OPTN_REGMAP_DEPTH-1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] regmap_tag_q       [0:OPTN_REGMAP_DEPTH-1];
    logic                          regmap_rdy_q       [0:OPTN_REGMAP_DEPTH-1];

    logic                          regmap_lookup_rdy  [0:1];
    logic [OPTN_DATA_WIDTH-1:0]    regmap_lookup_data [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] regmap_lookup_tag  [0:1];
    logic [OPTN_REGMAP_DEPTH-1:0]  retire_select;
    logic [OPTN_REGMAP_DEPTH-1:0]  rename_select;
    logic [OPTN_REGMAP_DEPTH-1:0]  regmap_rdy_mux;

    // Select vectors to enable writing to the registers whose select bit is set
    assign retire_select        = {(OPTN_REGMAP_DEPTH){i_regmap_retire_en}} & (1 << i_regmap_retire_rdest);
    assign rename_select        = {(OPTN_REGMAP_DEPTH){i_regmap_rename_en}} & (1 << i_regmap_rename_rdest);

    // FIXME: Output this register for architectural simulation test pass/fail detection
    assign o_sim_tp             = regmap_data_q[4];

    // We need to bypass data from the ROB retire interface when looking up mappings for source registers of the newly dispatched instruction
    always_comb begin
        for (int i = 0; i < 2; i++) begin
            logic                        lookup_bypass;
            logic [REGMAP_IDX_WIDTH-1:0] src;

            src                   = i_regmap_lookup_rsrc[i];
            lookup_bypass         = i_regmap_retire_en & ~regmap_rdy_q[src] & (regmap_tag_q[src] == i_regmap_retire_tag) & (i_regmap_retire_rdest == src);

            regmap_lookup_rdy[i]  = lookup_bypass | regmap_rdy_q[src];
            regmap_lookup_data[i] = lookup_bypass ? i_regmap_retire_data : regmap_data_q[src];
            regmap_lookup_tag[i]  = lookup_bypass ? i_regmap_retire_tag  : regmap_tag_q[src];
        end
    end

    always_comb begin
        for (int i = 0; i < OPTN_REGMAP_DEPTH; i++) begin
            logic [1:0] regmap_rdy_sel;

            regmap_rdy_sel = {retire_select[i], rename_select[i]};
            case (regmap_rdy_sel)
                2'b00: regmap_rdy_mux[i] = regmap_rdy_q[i];
                2'b01: regmap_rdy_mux[i] = 1'b0;
                2'b10: regmap_rdy_mux[i] = i_regmap_retire_tag == regmap_tag_q[i];
                2'b11: regmap_rdy_mux[i] = 1'b0;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (i_regmap_lookup_valid) begin
            o_regmap_lookup_rdy  <= regmap_lookup_rdy;
            o_regmap_lookup_data <= regmap_lookup_data;
            o_regmap_lookup_tag  <= regmap_lookup_tag;
        end
    end

    // The tags correspond to the ROB entry that will produce the value for that register
    // This is looked up for the source registers by each new instruction that is dispatched
    always_ff @(posedge clk) begin
        for (int i = 1; i < OPTN_REGMAP_DEPTH; i++) begin
            if (rename_select[i]) begin
                regmap_tag_q[i] <= i_regmap_rename_tag;
            end
        end
    end

    // The ROB updates the value of the destination register of the next retired instruction
    always_ff @(posedge clk) begin
        for (int i = 1; i < OPTN_REGMAP_DEPTH; i++) begin
           if (retire_select[i]) begin
                regmap_data_q[i] <= i_regmap_retire_data;
            end
        end
    end

    // If an exception/branch occurs then we need to throw away all the tags as those tags belong to instructions
    // that are now flushed and so won't produce the data. Luckily the register map already holds the latest
    // correct data for each register before the exception occurred and so all we need to do is set the ready bits
    // Tag updates take priority over retired instructions. The value from the retired instruction doesn't matter if
    // the same register will be updated by a next instruction dispatched. When an instruction is retired, the destination
    // register value is valid and the ready bit can be set but only if the latest tag for the register matches the tag of
    // the retiring instruction. Otherwise the data is not ready because a newer instruction will provide it
    always_ff @(posedge clk) begin
        for (int i = 1; i < OPTN_REGMAP_DEPTH; i++) begin
            if (~n_rst) regmap_rdy_q[i] <= 1'b1;
            else        regmap_rdy_q[i] <= i_flush | regmap_rdy_mux[i];
        end
    end

    // r0 should have correct values on reset
    always_ff @(posedge clk) begin
        regmap_data_q[0] <= {{(OPTN_DATA_WIDTH){1'b0}}};
        regmap_tag_q[0]  <= {{(OPTN_ROB_IDX_WIDTH){1'b0}}};
        regmap_rdy_q[0]  <= 1'b1;
    end

endmodule
