/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

module procyon_rat_entry #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                           clk,
    input  logic                           n_rst,

    // Flush signal -> Set all ready bits (basically invalidate tags)
    input  logic                           i_flush,

    // Output data, tag and ready bits
    output logic [OPTN_DATA_WIDTH-1:0]     o_rat_entry_data,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]  o_rat_entry_tag,
    output logic                           o_rat_entry_rdy,

    // Destination register update interface
    input  logic                           i_rat_retire_en,
    input  logic [OPTN_DATA_WIDTH-1:0]     i_rat_retire_data,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]  i_rat_retire_tag,

    // Tag update interface
    input  logic                           i_rat_rename_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]  i_rat_rename_tag
);

    // Each Register Alias Table entry will have a data value, tag and ready bit
    // The data value is updated when the ROB writes back to the destination register of a retired instruction
    // The tag is updated for the destination register whenever the ROB enqueues a new instruction
    // The ready bit is set when the ROB retires and writes back to that register or cleared when the instruction is
    // enqueued in the ROB
    logic [OPTN_DATA_WIDTH-1:0] rat_entry_data_r;
    logic [OPTN_ROB_IDX_WIDTH-1:0] rat_entry_tag_r;
    logic rat_entry_rdy_r;

    // If an exception/branch occurs then we need to throw away all the tags as those tags belong to instructions that
    // are now flushed and so won't produce the data. Luckily the register alias table already holds the latest correct data
    // for each register before the exception occurred and so all we need to do is set the ready bits. Tag updates take
    // priority over retired instructions. The value from the retired instruction doesn't matter if the same register
    // will be updated by a next instruction dispatched. When an instruction is retired, the destination register value
    // is valid and the ready bit can be set but only if the latest tag for the register matches the tag of the
    // retiring instruction. Otherwise the data is not ready because a newer instruction will provide it
    logic rat_entry_rdy_mux;

    always_comb begin
        logic [1:0] rat_rdy_sel;
        rat_rdy_sel = {i_rat_retire_en, i_rat_rename_en};

        unique case (rat_rdy_sel)
            2'b00: rat_entry_rdy_mux = rat_entry_rdy_r;
            2'b01: rat_entry_rdy_mux = 1'b0;
            2'b10: rat_entry_rdy_mux = (i_rat_retire_tag == rat_entry_tag_r);
            2'b11: rat_entry_rdy_mux = 1'b0;
        endcase

        rat_entry_rdy_mux = i_flush | rat_entry_rdy_mux;
    end

    procyon_srff #(1) rat_entry_rdy_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(rat_entry_rdy_mux), .i_reset(1'b1), .o_q(rat_entry_rdy_r));

    // The tags correspond to the ROB entry that will produce the value for that register. This is looked up for the
    // source registers by each new instruction that is dispatched
    procyon_ff #(OPTN_ROB_IDX_WIDTH) rat_entry_tag_ff (.clk(clk), .i_en(i_rat_rename_en), .i_d(i_rat_rename_tag), .o_q(rat_entry_tag_r));

    // The ROB updates the value of the destination register of the next retired instruction
    procyon_ff #(OPTN_DATA_WIDTH) rat_entry_data_ff (.clk(clk), .i_en(i_rat_retire_en), .i_d(i_rat_retire_data), .o_q(rat_entry_data_r));

    assign o_rat_entry_data = rat_entry_data_r;
    assign o_rat_entry_tag = rat_entry_tag_r;
    assign o_rat_entry_rdy = rat_entry_rdy_r;

endmodule
