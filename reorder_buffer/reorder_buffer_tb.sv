`define DATA_WIDTH 32
`define ADDR_WIDTH 32
`define REGMAP_DEPTH 32
`define ROB_DEPTH 64
`define TAG_WIDTH $clog2(`ROB_DEPTH)
`define REG_ADDR_WIDTH $clog2(`REGMAP_DEPTH)

import types::*;

module reorder_buffer_tb;

    logic clk;
    logic n_rst;

    logic o_redirect;
    logic [`ADDR_WIDTH-1:0] o_redirect_addr;

    always begin
        #10 clk = ~clk;
    end

    initial begin
        clk = 'b1;
        n_rst = 'b0;

        cdb.en = 'b0;
        cdb.redirect = 'b0;
        cdb.tag = 'b0;
        cdb.data = 'b0;
        cdb.addr = 'b0;
        rob_dispatch.en = 'b0;
        rob_dispatch.rdy = 'b0;
        rob_dispatch.op = ROB_OP_INT;
        rob_dispatch.iaddr = 'b0;
        rob_dispatch.data = 'b0;
        rob_dispatch.rdest = 'b0;
        rob_lookup.rsrc[0] = 'b0;
        rob_lookup.rsrc[1] = 'b0;
        
        #10 n_rst = 'b1;
    end

    cdb_if #(
        .ADDR_WIDTH(`ADDR_WIDTH),
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH)
    ) cdb ();

    rob_dispatch_if #(
        .ADDR_WIDTH(`ADDR_WIDTH),
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) rob_dispatch ();

    rob_lookup_if #(
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) rob_lookup ();

    regmap_dest_wr_if #(
        .DATA_WIDTH(`DATA_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) dest_wr ();

    regmap_tag_wr_if #(
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) tag_wr ();

    regmap_lookup_if #(
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) regmap_lookup ();

    reorder_buffer #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .ROB_DEPTH(`REGMAP_DEPTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) regmap (
        .clk(clk),
        .n_rst(n_rst),
        .o_redirect(o_redirect),
        .o_redirect_addr(o_redirect_addr),
        .cdb(cdb),
        .rob_dispatch(rob_dispatch),
        .rob_lookup(rob_lookup),
        .dest_wr(dest_wr),
        .tag_wr(tag_wr),
        .regmap_lookup(regmap_lookup)
    );

endmodule
