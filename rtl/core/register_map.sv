// Register Map with tag information for register renaming

`include "common.svh"
import procyon_types::*;

module register_map (
    input  logic           clk,
    input  logic           n_rst,

    // FIXME: Temporary for simulation pass/fail detection
    output procyon_data_t  o_sim_tp,

    // Flush signal -> Set all ready bits (basically invalidate tags)
    input  logic           i_flush,

    // Destination register update interface
    input  procyon_data_t  i_regmap_retire_data,
    input  procyon_reg_t   i_regmap_retire_rdest,
    input  procyon_tag_t   i_regmap_retire_tag,
    input  logic           i_regmap_retire_wr_en,

    // Tag update interface
    input  procyon_tag_t   i_regmap_rename_tag,
    input  procyon_reg_t   i_regmap_rename_rdest,
    input  logic           i_regmap_rename_wr_en,

    // Lookup source operand tag/data/rdy
    input  procyon_reg_t   i_regmap_lookup_rsrc [0:1],
    output logic           o_regmap_lookup_rdy  [0:1],
    output procyon_tag_t   o_regmap_lookup_tag  [0:1],
    output procyon_data_t  o_regmap_lookup_data [0:1]
);

    // Each Register Map entry will have a data value, tag and ready bit
    // The data value is updated when the ROB writes back to the destination register of a retired instruction
    // The tag is updated for the destination register whenever the ROB enqueues a new instruction
    // The ready bit is set when the ROB retires and writes back to that register or cleared when the instruction is enqueued in the ROB
    typedef struct packed {
        procyon_data_t data;
        procyon_tag_t  tag;
        logic          rdy;
    } regmap_t;

/* verilator lint_off MULTIDRIVEN */
    // Register r0 is special and should never be changed
    regmap_t                  regmap [`REGMAP_DEPTH-1:0];
/* verilator lint_on  MULTIDRIVEN */
    logic                     dest_wr_en;
    logic                     tag_wr_en;
    logic [`REGMAP_DEPTH-1:0] dest_wr_select;
    logic [`REGMAP_DEPTH-1:0] tag_wr_select;

    // We don't want to touch register r0 since it should always contain zero and cannot be changed
    // If any instruction tries to write to r0, it effectively means that instruction is throwing away the result
    assign dest_wr_en     = i_regmap_retire_wr_en && (i_regmap_retire_rdest != 'b0);
    assign tag_wr_en      = i_regmap_rename_wr_en && (i_regmap_rename_rdest != 'b0);

    // Select vectors to enable writing to the registers whose select bit is set
    assign dest_wr_select = 1 << i_regmap_retire_rdest;
    assign tag_wr_select  = 1 << i_regmap_rename_rdest;

    // FIXME: Output this register for architectural simulation test pass/fail detection
    assign o_sim_tp       = regmap[4].data;

    // The ROB will lookup tags/data for the source operands of the newly dispatched instruction
    genvar gvar;
    generate
        for (gvar = 0; gvar < 2; gvar++) begin : ASSIGN_REGMAP_LOOKUP_OUTPUTS
            assign o_regmap_lookup_rdy[gvar]  = regmap[i_regmap_lookup_rsrc[gvar]].rdy;
            assign o_regmap_lookup_data[gvar] = regmap[i_regmap_lookup_rsrc[gvar]].data;
            assign o_regmap_lookup_tag[gvar]  = regmap[i_regmap_lookup_rsrc[gvar]].tag;
        end
    endgenerate

    // The tags correspond to the ROB entry that will produce the value for that register
    // This is looked up for the source registers by each new instruction that is dispatched
    // We don't care about the reset values for the data/tags for these registers so these
    // flops should be inferred as rams by the synthesizer
    always_ff @(posedge clk) begin
        for (int i = 1; i < `REGMAP_DEPTH; i++) begin
            if (tag_wr_en && tag_wr_select[i]) begin
                regmap[i].tag <= i_regmap_rename_tag;
            end
        end
    end

    // The ROB updates the value of the destination register of the next retired instruction
    always_ff @(posedge clk) begin
        for (int i = 1; i < `REGMAP_DEPTH; i++) begin
            if (dest_wr_en && dest_wr_select[i]) begin
                regmap[i].data <= i_regmap_retire_data;
            end
        end
    end

    // The ready bit should be inferred as flip flops since they need to be reset to a value of 1
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 1; i < `REGMAP_DEPTH; i++) begin
            if (~n_rst) begin
                regmap[i].rdy <= 1'b1;
            end else if (i_flush) begin
                // If an exception/branch occurs then we need to throw away all the tags as those tags belong to instructions
                // that are now flushed and so won't produce the data. Luckily the register map already holds the latest
                // correct data for each register before the exception occurred and so all we need to do is set the ready bits
                regmap[i].rdy <= 1'b1;
            end else if (tag_wr_en && tag_wr_select[i]) begin
                // Tag updates take priority over retired instructions
                // The value from the retired instruction doesn't matter if the same register will be updated
                // by a next instruction dispatched
                regmap[i].rdy <= 1'b0;
            end else if (dest_wr_en && dest_wr_select[i]) begin
                // When an instruction is retired, the destination register value is valid and the ready bit can be set
                // But only if the latest tag for the register matches the tag of the retiring instruction
                // Otherwise the data is not ready because a newer instruction will provide it
                regmap[i].rdy <= (i_regmap_retire_tag == regmap[i].tag) ? 1'b1 : 1'b0;
            end
        end
    end

    // r0 should have correct values on reset
    always_ff @(posedge clk) begin
        regmap[0].data <= {{(`DATA_WIDTH){1'b0}}};
        regmap[0].tag  <= {{(`TAG_WIDTH){1'b0}}};
        regmap[0].rdy  <= 1'b1;
    end

endmodule
