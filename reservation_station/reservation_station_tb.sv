`timescale 1ns/1ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 32
`define TAG_WIDTH  6
`define REG_ADDR_WIDTH 5

`define REGMAP_DEPTH 32
`define ROB_DEPTH 64
`define RS_DEPTH 8

`define NOOP 32'h00000013 // ADDI X0, X0, #0

import types::*;

module reservation_station_tb;

    logic clk;
    logic n_rst;

    logic i_flush;
    logic o_redirect;
    logic [`ADDR_WIDTH-1:0] o_redirect_addr;

    // Clock generation
    initial clk = 'b1;
    always #10 clk = ~clk;

    initial begin
        n_rst = 'b0;
        i_flush = 'b0;
        insn_fifo_wr.wr_en = 'b0;
        insn_fifo_wr.data_in = 'b0;
        cdb.en = 'b0;
        cdb.data = 'b0;
        cdb.addr = 'b0;
        cdb.tag = 'b0;
        cdb.redirect = 'b0;

        for (int i = 0; i < `ROB_DEPTH; i++) begin
            rob.rob.entries[i] = '{rdy: 'b0, redirect: 'b0, op: ROB_OP_INT, iaddr: 'b0, addr: 'b0, data: 'b0, rdest: 'b0};
        end

        for (int i = 0; i < `REGMAP_DEPTH; i++) begin
            register_map_inst.regmap[i] = '{rdy: 'b0, tag: 'b0, data: 'b0};
        end

        for (int i = 0; i < `RS_DEPTH; i++) begin
            rs_inst.rs.slots[i] = '{age: 'b0, opcode: OPCODE_OPIMM, iaddr: 'b0, insn: 32'h00000013, src_rdy: '{'b0, 'b0}, src_data: '{'b0, 'b0}, src_tag: '{'b0, 'b0}, dst_tag: 'b0};
        end

        #20 n_rst = 'b1;

        insn_fifo_wr.data_in = {32'b0, `NOOP};
        insn_fifo_wr.wr_en   = 'b1;

        #20 insn_fifo_wr.data_in = {32'h4, 32'habc00093};

        #20 insn_fifo_wr.wr_en = 'b0;

    end

    // Interfaces
    fifo_wr_if #(
        .DATA_WIDTH(`ADDR_WIDTH+`DATA_WIDTH)
    ) insn_fifo_wr ();

    fifo_rd_if #(
        .DATA_WIDTH(`ADDR_WIDTH+`DATA_WIDTH)
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

    rs_funit_if #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH)
    ) rs_funit ();

    // Module Instances
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

    reservation_station #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .RS_DEPTH(`RS_DEPTH)
    ) rs_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .rs_dispatch(rs_dispatch),
        .rs_funit(rs_funit)
    );

endmodule
