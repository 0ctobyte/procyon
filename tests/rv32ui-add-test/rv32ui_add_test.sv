`timescale 1ns/1ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 32
`define TAG_WIDTH  6
`define REG_ADDR_WIDTH 5

`define ROM_DEPTH 512
`define REGMAP_DEPTH 32
`define ROB_DEPTH 64
`define RS_DEPTH 8
`define IEU_FIFO_DEPTH 8

`define ROM_BASE_ADDR 32'h0
`define ROM_FILE "rv32ui-add.hex"

`define NOOP 32'h00000013 // ADDI X0, X0, #0

import types::*;

module rv32ui_add_test;

    logic clk;
    logic n_rst;

    logic rob_redirect;
    logic [`ADDR_WIDTH-1:0] rob_redirect_addr;

    logic [`ADDR_WIDTH-1:0] fetch_pc;
    logic                   fetch_en;
    logic [`DATA_WIDTH-1:0] rom_data_out;
    logic                   rom_data_valid;
    logic [$clog2(`ROM_DEPTH)-1:0] rom_rd_addr;

    always_comb begin
        logic [`ADDR_WIDTH-1:0] t;
        t = fetch_pc >> 2;
        rom_rd_addr = t[$clog2(`ROM_DEPTH)-1:0];
    end

    assign rom_data_valid = fetch_en;

    assign arb.gnt = arb.req;

    assign cdb.en       = arb.gnt ? 'bz : 'b0;
    assign cdb.data     = arb.gnt ? 'bz : 'b0;
    assign cdb.addr     = arb.gnt ? 'bz : 'b0;
    assign cdb.tag      = arb.gnt ? 'bz : 'b0;
    assign cdb.redirect = arb.gnt ? 'bz : 'b0;

    // Clock generation
    initial clk = 'b1;
    always #10 clk = ~clk;

    initial begin
        n_rst = 'b0;

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

    arbiter_if arb ();

    // Module Instances
    rom #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ROM_DEPTH(`ROM_DEPTH),
        .BASE_ADDR(`ROM_BASE_ADDR),
        .ROM_FILE(`ROM_FILE)
    ) boot_rom (
        .clk(clk),
        .n_rst(n_rst),
        .i_rd_addr(rom_rd_addr),
        .o_data_out(rom_data_out)
    );

    simple_fetch #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH)
    ) simple_fetch_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_redirect(rob_redirect),
        .i_redirect_addr(rob_redirect_addr),
        .i_insn(rom_data_out),
        .i_data_valid(rom_data_valid),
        .o_pc(fetch_pc),
        .o_en(fetch_en),
        .insn_fifo_wr(insn_fifo_wr)
    );

    sync_fifo #(
        .DATA_WIDTH(`ADDR_WIDTH+`DATA_WIDTH),
        .FIFO_DEPTH(8)
    ) insn_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .if_fifo_wr(insn_fifo_wr),
        .if_fifo_rd(insn_fifo_rd)
    );

    dispatch #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) dispatch_inst (
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
        .i_flush(rob_redirect),
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
        .o_redirect(rob_redirect),
        .o_redirect_addr(rob_redirect_addr),
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
        .i_flush(rob_redirect),
        .rs_dispatch(rs_dispatch),
        .rs_funit(rs_funit)
    );

    ieu #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .IEU_FIFO_DEPTH(`IEU_FIFO_DEPTH)
    ) ieu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .cdb(cdb),
        .rs_funit(rs_funit),
        .arb(arb)
    );

endmodule
