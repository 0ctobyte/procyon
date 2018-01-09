// Register Map with tag information for register renaming

`include "common.svh"

module register_map #(
    parameter DATA_WIDTH      = `DATA_WIDTH,
    parameter REGMAP_DEPTH    = `ADDR_WIDTH,
    parameter TAG_WIDTH       = `TAG_WIDTH
) (
    input  logic                              clk,
    input  logic                              n_rst,

    // Flush signal -> Set all ready bits (basically invalidate tags)
    input  logic                              i_flush,

    // Destination register update interface
    input  logic [DATA_WIDTH-1:0]             i_regmap_retire_data,
    input  logic [$clog2(REGMAP_DEPTH)-1:0]   i_regmap_retire_rdest,
    input  logic [TAG_WIDTH-1:0]              i_regmap_retire_tag,
    input  logic                              i_regmap_retire_wr_en,

    // Tag update interface
    input  logic [TAG_WIDTH-1:0]              i_regmap_rename_tag,
    input  logic [$clog2(REGMAP_DEPTH)-1:0]   i_regmap_rename_rdest,
    input  logic                              i_regmap_rename_wr_en,

    // Lookup source operand tag/data/rdy
    input  logic [$clog2(REGMAP_DEPTH)-1:0]   i_regmap_lookup_rsrc [0:1],
    output logic                              o_regmap_lookup_rdy  [0:1],
    output logic [TAG_WIDTH-1:0]              o_regmap_lookup_tag  [0:1],
    output logic [DATA_WIDTH-1:0]             o_regmap_lookup_data [0:1]
);

    // Each Register Map entry will have a data value, tag and ready bit
    // The data value is updated when the ROB writes back to the destination register of a retired instruction
    // The tag is updated for the destination register whenever the ROB enqueues a new instruction
    // The ready bit is set when the ROB retires and writes back to that register or cleared when the instruction is enqueued in the ROB
    typedef struct packed {
        logic [DATA_WIDTH-1:0] data;
        logic [TAG_WIDTH-1:0]  tag;
        logic                  rdy;
    } regmap_t;

    // Register r0 is special and should never be changed
    regmap_t regmap [REGMAP_DEPTH-1:0];

    logic                    dest_wr_en;
    logic                    tag_wr_en;

    logic [REGMAP_DEPTH-1:0] dest_wr_select;
    logic [REGMAP_DEPTH-1:0] tag_wr_select;

    // We don't want to touch register r0 since it should always contain zero and cannot be changed
    // If any instruction tries to write to r0, it effectively means that instruction is throwing away the result
    assign dest_wr_en     = i_regmap_retire_wr_en && (i_regmap_retire_rdest != 'b0);
    assign tag_wr_en      = i_regmap_rename_wr_en && (i_regmap_rename_rdest != 'b0);

    // Select vectors to enable writing to the registers whose select bit is set
    assign dest_wr_select = 1 << i_regmap_retire_rdest;
    assign tag_wr_select  = 1 << i_regmap_rename_rdest;

    // The ROB will lookup tags/data for the source operands of the newly dispatched instruction
    genvar i;
    generate
    for (i = 0; i < 2; i++) begin : ASSIGN_REGMAP_LOOKUP_OUTPUTS
        assign o_regmap_lookup_rdy[i]  = regmap[i_regmap_lookup_rsrc[i]].rdy; 
        assign o_regmap_lookup_data[i] = regmap[i_regmap_lookup_rsrc[i]].data; 
        assign o_regmap_lookup_tag[i]  = regmap[i_regmap_lookup_rsrc[i]].tag; 
    end
    endgenerate

    // The tags correspond to the ROB entry that will produce the value for that register
    // This is looked up for the source registers by each new instruction that is dispatched 
    // We don't care about the reset values for the data/tags for these registers so these
    // flops should be inferred as rams by the synthesizer
    always_ff @(posedge clk) begin
        for (int i = 1; i < REGMAP_DEPTH; i++) begin
            if (tag_wr_en && tag_wr_select[i]) begin
                regmap[i].tag <= i_regmap_rename_tag;
            end
        end
    end

    // The ROB updates the value of the destination register of the next retired instruction
    always_ff @(posedge clk) begin
        for (int i = 1; i < REGMAP_DEPTH; i++) begin
            if (dest_wr_en && dest_wr_select[i]) begin
                regmap[i].data <= i_regmap_retire_data;
            end
        end
    end

    // The ready bit should be inferred as flip flops since they need to be reset to a value of 1
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 1; i < REGMAP_DEPTH; i++) begin
            if (~n_rst) begin
                regmap[i].rdy <= 'b1;
            end else if (i_flush) begin
                // If an exception/branch occurs then we need to throw away all the tags as those tags belong to instructions
                // that are now flushed and so won't produce the data. Luckily the register map already holds the latest
                // correct data for each register before the exception occurred and so all we need to do is set the ready bits
                regmap[i].rdy <= 'b1;
            end else if (tag_wr_en && tag_wr_select[i]) begin
                // Tag updates take priority over retired instructions
                // The value from the retired instruction doesn't matter if the same register will be updated
                // by a next instruction dispatched
                regmap[i].rdy <= 'b0;
            end else if (dest_wr_en && dest_wr_select[i]) begin
                // When an instruction is retired, the destination register value is valid and the ready bit can be set
                // But only if the latest tag for the register matches the tag of the retiring instruction
                // Otherwise the data is not ready because a newer instruction will provide it
                regmap[i].rdy <= (i_regmap_retire_tag == regmap[i].tag) ? 'b1 : 'b0;
            end
        end
    end

    // r0 should have correct values on reset
    always_ff @(posedge clk) begin
        regmap[0].data <= 'b0;
        regmap[0].tag  <= 'b0;
        regmap[0].rdy  <= 'b1;
    end
            
endmodule
