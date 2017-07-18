`timescale 1ns/1ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 32
`define TAG_WIDTH  6
`define REG_ADDR_WIDTH 5

`define REGMAP_DEPTH 32
`define ROB_DEPTH 64

module dispatch_tb;

    logic clk;
    logic n_rst;

    logic i_flush;
    logic o_redirect;
    logic [`ADDR_WIDTH-1:0] o_redirect_addr;

    // Clock generation
    initial clk = 'b0;
    always #10 clk = ~clk;

    initial begin
        n_rst = 'b0;
        i_flush = 'b0;
        rs_dispatch.stall = 'b0;
        insn_fifo_wr.wr_en = 'b0;
        insn_fifo_wr.data_in = 'b0;
        cdb.en = 'b0;
        cdb.data = 'b0;
        cdb.addr = 'b0;
        cdb.tag = 'b0;
        cdb.redirect = 'b0;

        #20 n_rst = 'b1;
    end

    // Interfaces
    fifo_wr_if #(
        .DATA_WIDTH(`DATA_WIDTH)
    ) insn_fifo_wr ();

    fifo_rd_if #(
        .DATA_WIDTH(`DATA_WIDTH)
    ) insn_fifo_rd ();

    cdb_if #(
        .ADDR_WIDTH(`ADDR_WIDTH),
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH)
    ) cdb ();

    regmap_dest_wr_if #(
        .DATA_WIDTH(`DATA_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) regmap_dest_wr ();

    regmap_tag_wr_if #(
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) regmap_tag_wr ();

    regmap_lookup_if #(
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) regmap_lookup ();

    rs_dispatch_if #(
        .ADDR_WIDTH(`ADDR_WIDTH),
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) rs_dispatch ();

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

    sync_fifo #(
        .DATA_WIDTH(`ADDR_WIDTH+`DATA_WIDTH),
        .FIFO_DEPTH(8)
    ) insn_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .if_fifo_wr(insn_fifo_wr),
        .if_fifo_rd(insn_fifo_rd)
    );

    // Module Instances
    dispatch #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .n_rst(n_rst),
        .insn_fifo_rd(insn_fifo_rd),
        .rs_dispatch(rs_dispatch),
        .rob_dispatch(rob_dispatch),
        .rob_lookup(rob_lookup)
    );

    register_map #(
        .DATA_WIDTH(`DATA_WIDTH),
        .REGMAP_DEPTH(`REGMAP_DEPTH),
        .TAG_WIDTH(`TAG_WIDTH)
    ) register_map_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .dest_wr(regmap_dest_wr),
        .tag_wr(regmap_tag_wr),
        .regmap_lookup(regmap_lookup)
    );

    reorder_buffer #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .ROB_DEPTH(`ROB_DEPTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) rob (
        .clk(clk),
        .n_rst(n_rst),
        .o_redirect(o_redirect),
        .o_redirect_addr(o_redirect_addr),
        .cdb(cdb),
        .rob_dispatch(rob_dispatch),
        .rob_lookup(rob_lookup),
        .dest_wr(regmap_dest_wr),
        .tag_wr(regmap_tag_wr),
        .regmap_lookup(regmap_lookup)
    );

endmodule
