`timescale 1ns/1ns

`include "../../rtl/common.svh"

`define ROM_DEPTH 512
`define ROM_BASE_ADDR 32'h0

`define NOOP 32'h00000013 // ADDI X0, X0, #0

import types::*;

module rv32ui_test_tb #(
    parameter ROM_FILE = "rv32ui-p-add.hex"
);

    logic clk;
    logic n_rst;

    // Module signals
    logic                           insn_fifo_empty;
    logic [`DATA_WIDTH-1:0]         insn_fifo_rd_data;
    logic                           insn_fifo_rd_en;
    logic                           insn_fifo_full;
    logic [`DATA_WIDTH-1:0]         insn_fifo_wr_data;
    logic                           insn_fifo_wr_en;

    logic                           iaddr_fifo_empty;
    logic [`ADDR_WIDTH-1:0]         iaddr_fifo_rd_data;
    logic                           iaddr_fifo_rd_en;
    logic                           iaddr_fifo_full;
    logic [`ADDR_WIDTH-1:0]         iaddr_fifo_wr_data;
    logic                           iaddr_fifo_wr_en;

    logic                           rs_stall;
    logic                           rs_en;
    opcode_t                        rs_opcode;
    logic [`ADDR_WIDTH-1:0]         rs_iaddr;
    logic [`DATA_WIDTH-1:0]         rs_insn;
    logic [`TAG_WIDTH-1:0]          rs_src_tag  [0:1];
    logic [`DATA_WIDTH-1:0]         rs_src_data [0:1];
    logic                           rs_src_rdy  [0:1];
    logic [`TAG_WIDTH-1:0]          rs_dst_tag;

    logic                           rob_stall;
    logic [`TAG_WIDTH-1:0]          rob_tag;
    logic                           rob_src_rdy  [0:1];
    logic [`DATA_WIDTH-1:0]         rob_src_data [0:1];
    logic [`TAG_WIDTH-1:0]          rob_src_tag  [0:1];
    logic                           rob_en;
    logic                           rob_rdy;
    rob_op_t                        rob_op;
    logic [`ADDR_WIDTH-1:0]         rob_iaddr;
    logic [`ADDR_WIDTH-1:0]         rob_addr;
    logic [`DATA_WIDTH-1:0]         rob_data;
    logic [`REG_ADDR_WIDTH-1:0]     rob_rdest;
    logic [`REG_ADDR_WIDTH-1:0]     rob_rsrc     [0:1];

    logic [`DATA_WIDTH-1:0]         regmap_retire_data;
    logic [`REG_ADDR_WIDTH-1:0]     regmap_retire_rdest;
    logic [$clog2(`ROB_DEPTH)-1:0]  regmap_retire_tag;
    logic                           regmap_retire_wr_en;

    logic [$clog2(`ROB_DEPTH)-1:0]  regmap_rename_tag;
    logic [`REG_ADDR_WIDTH-1:0]     regmap_rename_rdest;
    logic                           regmap_rename_wr_en;

    logic                           regmap_lookup_rdy  [0:1];
    logic [$clog2(`ROB_DEPTH)-1:0]  regmap_lookup_tag  [0:1];
    logic [`DATA_WIDTH-1:0]         regmap_lookup_data [0:1];
    logic [`REG_ADDR_WIDTH-1:0]     regmap_lookup_rsrc [0:1];

    logic                           fu_stall;
    logic                           fu_valid;
    opcode_t                        fu_opcode;
    logic [`ADDR_WIDTH-1:0]         fu_iaddr;
    logic [`DATA_WIDTH-1:0]         fu_insn;
    logic [`DATA_WIDTH-1:0]         fu_src_a;
    logic [`DATA_WIDTH-1:0]         fu_src_b;
    logic [`TAG_WIDTH-1:0]          fu_tag;


    logic rob_redirect;
    logic [`ADDR_WIDTH-1:0] rob_redirect_addr;

    logic [`ADDR_WIDTH-1:0] fetch_pc;
    logic                   fetch_en;
    logic [`DATA_WIDTH-1:0] rom_data_out;
    logic                   rom_data_valid;
    logic [$clog2(`ROM_DEPTH)-1:0] rom_rd_addr;

    assign rom_data_valid = fetch_en;

    // Clock generation
    initial clk = 'b1;
    always #10 clk = ~clk;

    initial begin
        $display("Test File: %s\n", ROM_FILE);

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

    always_comb begin
        logic [`ADDR_WIDTH-1:0] t;
        t = fetch_pc >> 2;
        rom_rd_addr = t[$clog2(`ROM_DEPTH)-1:0];
    end

    always @(posedge clk) begin
        if (register_map_inst.regmap[3].rdy && register_map_inst.regmap[3].data == 32'hfffffae5) begin
            $display("---------FAIL---------\n");
            $stop;
        end else if (register_map_inst.regmap[3].rdy && register_map_inst.regmap[3].data == 32'hfffffbd2) begin
            $display("---------PASS---------\n");
            $stop;
        end
    end

    cdb_if #(
        .ADDR_WIDTH(`ADDR_WIDTH),
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH)
    ) cdb ();

    // Module Instances
    rom #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ROM_DEPTH(`ROM_DEPTH),
        .BASE_ADDR(`ROM_BASE_ADDR),
        .ROM_FILE(ROM_FILE)
    ) boot_rom (
        .clk(clk),
        .n_rst(n_rst),
        .i_rom_rd_addr(rom_rd_addr),
        .o_rom_data_out(rom_data_out)
    );

    fetch #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH)
    ) fetch_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_redirect(rob_redirect),
        .i_redirect_addr(rob_redirect_addr),
        .i_insn(rom_data_out),
        .i_data_valid(rom_data_valid),
        .o_pc(fetch_pc),
        .o_en(fetch_en),
        .i_insn_fifo_full(insn_fifo_full),
        .o_insn_fifo_data(insn_fifo_wr_data),
        .o_insn_fifo_wr_en(insn_fifo_wr_en),
        .i_iaddr_fifo_full(iaddr_fifo_full),
        .o_iaddr_fifo_data(iaddr_fifo_wr_data),
        .o_iaddr_fifo_wr_en(iaddr_fifo_wr_en)
    );

    sync_fifo #(
        .DATA_WIDTH(`DATA_WIDTH),
        .FIFO_DEPTH(8)
    ) insn_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .i_fifo_rd_en(insn_fifo_rd_en),
        .o_fifo_data(insn_fifo_rd_data),
        .o_fifo_empty(insn_fifo_empty),
        .i_fifo_wr_en(insn_fifo_wr_en),
        .i_fifo_data(insn_fifo_wr_data),
        .o_fifo_full(insn_fifo_full)
    );

    sync_fifo #(
        .DATA_WIDTH(`ADDR_WIDTH),
        .FIFO_DEPTH(8)
    ) iaddr_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .i_fifo_rd_en(iaddr_fifo_rd_en),
        .o_fifo_data(iaddr_fifo_rd_data),
        .o_fifo_empty(iaddr_fifo_empty),
        .i_fifo_wr_en(iaddr_fifo_wr_en),
        .i_fifo_data(iaddr_fifo_wr_data),
        .o_fifo_full(iaddr_fifo_full)
    );

    dispatch #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) dispatch_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_insn_fifo_empty(insn_fifo_empty),
        .i_insn_fifo_data(insn_fifo_rd_data),
        .o_insn_fifo_rd_en(insn_fifo_rd_en),
        .i_iaddr_fifo_empty(iaddr_fifo_empty),
        .i_iaddr_fifo_data(iaddr_fifo_rd_data),
        .o_iaddr_fifo_rd_en(iaddr_fifo_rd_en),
        .i_rs_stall(rs_stall),
        .o_rs_en(rs_en),
        .o_rs_opcode(rs_opcode),
        .o_rs_iaddr(rs_iaddr),
        .o_rs_insn(rs_insn),
        .o_rs_src_tag(rs_src_tag),
        .o_rs_src_data(rs_src_data),
        .o_rs_src_rdy(rs_src_rdy),
        .o_rs_dst_tag(rs_dst_tag),
        .i_rob_stall(rob_stall),
        .i_rob_tag(rob_tag),
        .i_rob_src_rdy(rob_src_rdy),
        .i_rob_src_data(rob_src_data),
        .i_rob_src_tag(rob_src_tag),
        .o_rob_en(rob_en),
        .o_rob_rdy(rob_rdy),
        .o_rob_op(rob_op),
        .o_rob_iaddr(rob_iaddr),
        .o_rob_addr(rob_addr),
        .o_rob_data(rob_data),
        .o_rob_rdest(rob_rdest),
        .o_rob_rsrc(rob_rsrc)
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
        .i_rob_en(rob_en),
        .i_rob_rdy(rob_rdy),
        .i_rob_op(rob_op),
        .i_rob_iaddr(rob_iaddr),
        .i_rob_addr(rob_addr),
        .i_rob_data(rob_data),
        .i_rob_rdest(rob_rdest),
        .i_rob_rsrc(rob_rsrc),
        .o_rob_tag(rob_tag),
        .o_rob_src_data(rob_src_data),
        .o_rob_src_tag(rob_src_tag),
        .o_rob_src_rdy(rob_src_rdy),
        .o_rob_stall(rob_stall),
        .o_regmap_retire_data(regmap_retire_data),
        .o_regmap_retire_rdest(regmap_retire_rdest),
        .o_regmap_retire_tag(regmap_retire_tag),
        .o_regmap_retire_wr_en(regmap_retire_wr_en),
        .o_regmap_rename_tag(regmap_rename_tag),
        .o_regmap_rename_rdest(regmap_rename_rdest),
        .o_regmap_rename_wr_en(regmap_rename_wr_en),
        .i_regmap_lookup_rdy(regmap_lookup_rdy),
        .i_regmap_lookup_tag(regmap_lookup_tag),
        .i_regmap_lookup_data(regmap_lookup_data),
        .o_regmap_lookup_rsrc(regmap_lookup_rsrc)
    );

    register_map #(
        .DATA_WIDTH(`DATA_WIDTH),
        .REGMAP_DEPTH(`REGMAP_DEPTH),
        .TAG_WIDTH(`TAG_WIDTH)
    ) register_map_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .i_regmap_retire_data(regmap_retire_data),
        .i_regmap_retire_rdest(regmap_retire_rdest),
        .i_regmap_retire_tag(regmap_retire_tag),
        .i_regmap_retire_wr_en(regmap_retire_wr_en),
        .i_regmap_rename_tag(regmap_rename_tag),
        .i_regmap_rename_rdest(regmap_rename_rdest),
        .i_regmap_rename_wr_en(regmap_rename_wr_en),
        .i_regmap_lookup_rsrc(regmap_lookup_rsrc),
        .o_regmap_lookup_rdy(regmap_lookup_rdy),
        .o_regmap_lookup_tag(regmap_lookup_tag),
        .o_regmap_lookup_data(regmap_lookup_data)
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
        .cdb(cdb),
        .i_rs_en(rs_en),
        .i_rs_opcode(rs_opcode),
        .i_rs_iaddr(rs_iaddr),
        .i_rs_insn(rs_insn),
        .i_rs_src_tag(rs_src_tag),
        .i_rs_src_data(rs_src_data),
        .i_rs_src_rdy(rs_src_rdy),
        .i_rs_dst_tag(rs_dst_tag),
        .o_rs_stall(rs_stall),
        .i_fu_stall(fu_stall),
        .o_fu_valid(fu_valid),
        .o_fu_opcode(fu_opcode),
        .o_fu_iaddr(fu_iaddr),
        .o_fu_insn(fu_insn),
        .o_fu_src_a(fu_src_a),
        .o_fu_src_b(fu_src_b),
        .o_fu_tag(fu_tag)
    );

    ieu #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH)
    ) ieu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .cdb(cdb),
        .i_fu_valid(fu_valid),
        .i_fu_opcode(fu_opcode),
        .i_fu_iaddr(fu_iaddr),
        .i_fu_insn(fu_insn),
        .i_fu_src_a(fu_src_a),
        .i_fu_src_b(fu_src_b),
        .i_fu_tag(fu_tag),
        .o_fu_stall(fu_stall)
    );

endmodule
