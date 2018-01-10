`timescale 1ns/1ns

`include "../../rtl/common.svh"

`define ROM_DEPTH 512
`define ROM_BASE_ADDR 32'h0

`define NOOP 32'h00000013 // ADDI X0, X0, #0

import types::*;

module rv32ui_synthesis_test #(
    parameter ROM_FILE = "rv32ui-p-add.hex"
) (
    input  logic         CLOCK_50,
    input  logic [17:17] SW,

    input  logic [0:0]   KEY,

    output logic [6:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7
);
    // Module signals
    logic                                 insn_fifo_empty;
    logic [`ADDR_WIDTH+`DATA_WIDTH-1:0]   insn_fifo_rd_data;
    logic                                 insn_fifo_rd_en;
    logic                                 insn_fifo_full;
    logic [`ADDR_WIDTH+`DATA_WIDTH-1:0]   insn_fifo_wr_data;
    logic                                 insn_fifo_wr_en;

    logic                                 rs_stall;
    logic                                 rs_en;
    opcode_t                              rs_opcode;
    logic [`ADDR_WIDTH-1:0]               rs_iaddr;
    logic [`DATA_WIDTH-1:0]               rs_insn;
    logic [`TAG_WIDTH-1:0]                rs_src_tag  [0:1];
    logic [`DATA_WIDTH-1:0]               rs_src_data [0:1];
    logic                                 rs_src_rdy  [0:1];
    logic [`TAG_WIDTH-1:0]                rs_dst_tag;

    logic                                 rob_stall;
    logic [`TAG_WIDTH-1:0]                rob_tag;
    logic                                 rob_src_rdy  [0:1];
    logic [`DATA_WIDTH-1:0]               rob_src_data [0:1];
    logic [`TAG_WIDTH-1:0]                rob_src_tag  [0:1];
    logic                                 rob_en;
    logic                                 rob_rdy;
    rob_op_t                              rob_op;
    logic [`ADDR_WIDTH-1:0]               rob_iaddr;
    logic [`ADDR_WIDTH-1:0]               rob_addr;
    logic [`DATA_WIDTH-1:0]               rob_data;
    logic [`REG_ADDR_WIDTH-1:0]           rob_rdest;
    logic [`REG_ADDR_WIDTH-1:0]           rob_rsrc     [0:1];

    logic [`DATA_WIDTH-1:0]               regmap_retire_data;
    logic [`REG_ADDR_WIDTH-1:0]           regmap_retire_rdest;
    logic [$clog2(`ROB_DEPTH)-1:0]        regmap_retire_tag;
    logic                                 regmap_retire_wr_en;

    logic [$clog2(`ROB_DEPTH)-1:0]        regmap_rename_tag;
    logic [`REG_ADDR_WIDTH-1:0]           regmap_rename_rdest;
    logic                                 regmap_rename_wr_en;

    logic                                 regmap_lookup_rdy  [0:1];
    logic [$clog2(`ROB_DEPTH)-1:0]        regmap_lookup_tag  [0:1];
    logic [`DATA_WIDTH-1:0]               regmap_lookup_data [0:1];
    logic [`REG_ADDR_WIDTH-1:0]           regmap_lookup_rsrc [0:1];

    logic                                 fu_stall  [0:`CDB_DEPTH-1];
    logic                                 fu_valid  [0:`CDB_DEPTH-1];
    opcode_t                              fu_opcode [0:`CDB_DEPTH-1];
    logic [`ADDR_WIDTH-1:0]               fu_iaddr  [0:`CDB_DEPTH-1];
    logic [`DATA_WIDTH-1:0]               fu_insn   [0:`CDB_DEPTH-1];
    logic [`DATA_WIDTH-1:0]               fu_src_a  [0:`CDB_DEPTH-1];
    logic [`DATA_WIDTH-1:0]               fu_src_b  [0:`CDB_DEPTH-1];
    logic [`TAG_WIDTH-1:0]                fu_tag    [0:`CDB_DEPTH-1];

    logic                                 cdb_en       [0:`CDB_DEPTH-1];
    logic                                 cdb_redirect [0:`CDB_DEPTH-1];
    logic [`DATA_WIDTH-1:0]               cdb_data     [0:`CDB_DEPTH-1];
    logic [`ADDR_WIDTH-1:0]               cdb_addr     [0:`CDB_DEPTH-1];
    logic [`TAG_WIDTH-1:0]                cdb_tag      [0:`CDB_DEPTH-1];


    typedef enum logic {
        RUN  = 1'b0,
        HALT = 1'b1
    } state_t;
    state_t state;

    logic clk;
    logic key, key_pulse;

    logic rob_redirect;
    logic [`ADDR_WIDTH-1:0] rob_redirect_addr;

    logic [`ADDR_WIDTH-1:0] fetch_pc;
    logic                   fetch_en;
    logic [`DATA_WIDTH-1:0] rom_data_out;
    logic                   rom_data_valid;
    logic [$clog2(`ROM_DEPTH)-1:0] rom_rd_addr;

    logic rs_en_flip;
    logic [`CDB_DEPTH-1:0] rs_en_m;
    logic [`CDB_DEPTH-1:0] rs_stall_m;

    logic [6:0] o_hex [0:7];

    assign key = ~KEY[0];

    assign rs_en_m    = rs_en_flip ? {1'b0, rs_en} : {rs_en, 1'b0};
    assign rs_stall   = |rs_stall_m;

    assign rom_data_valid = fetch_en;

    assign HEX0 = o_hex[0];
    assign HEX1 = o_hex[1];
    assign HEX2 = o_hex[2];
    assign HEX3 = o_hex[3];
    assign HEX4 = o_hex[4];
    assign HEX5 = o_hex[5];
    assign HEX6 = o_hex[6];
    assign HEX7 = o_hex[7];

    always_comb begin
        case (state)
            RUN:  clk = CLOCK_50;
            HALT: clk = 'b0;
        endcase
    end

    always_ff @(posedge CLOCK_50, negedge SW[17]) begin
        if (~SW[17]) begin
            state <= RUN;
        end else begin
            case (state)
                RUN:  state <= regmap_retire_wr_en ? HALT : RUN;
                HALT: state <= key_pulse ? RUN : HALT;
            endcase
        end
    end

    always_comb begin
        logic [`ADDR_WIDTH-1:0] t;
        t = fetch_pc >> 2;
        rom_rd_addr = t[$clog2(`ROM_DEPTH)-1:0];
    end

    always @(posedge clk, negedge SW[17]) begin
        if (~SW[17]) begin
            rs_en_flip <= 1'b0;
        end else begin
            rs_en_flip <= rs_en_flip ^ 1'b1;
        end
    end

    genvar i;
    generate
    for (i = 0; i < 8; i++) begin : SEG7_DECODER_INSTANCES
        seg7_decoder seg7_decoder_inst (
            .n_rst(SW[17]),
            .i_hex(regmap_retire_data[i*4+3:i*4]),
            .o_hex(o_hex[i])
        );
    end
    endgenerate

    edge_detector edge_detector_inst (
        .clk(CLOCK_50),
        .n_rst(SW[17]),
        .i_async(key),
        .o_pulse(key_pulse)
    );

    // Module Instances
    rom #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ROM_DEPTH(`ROM_DEPTH),
        .BASE_ADDR(`ROM_BASE_ADDR),
        .ROM_FILE(ROM_FILE)
    ) boot_rom (
        .clk(clk),
        .n_rst(SW[17]),
        .i_rom_rd_addr(rom_rd_addr),
        .o_rom_data_out(rom_data_out)
    );

    fetch #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH)
    ) fetch_inst (
        .clk(clk),
        .n_rst(SW[17]),
        .i_redirect(rob_redirect),
        .i_redirect_addr(rob_redirect_addr),
        .i_insn(rom_data_out),
        .i_data_valid(rom_data_valid),
        .o_pc(fetch_pc),
        .o_en(fetch_en),
        .i_insn_fifo_full(insn_fifo_full),
        .o_insn_fifo_data(insn_fifo_wr_data),
        .o_insn_fifo_wr_en(insn_fifo_wr_en)
    );

    sync_fifo #(
        .DATA_WIDTH(`ADDR_WIDTH+`DATA_WIDTH),
        .FIFO_DEPTH(8)
    ) insn_fifo (
        .clk(clk),
        .n_rst(SW[17]),
        .i_flush(rob_redirect),
        .i_fifo_rd_en(insn_fifo_rd_en),
        .o_fifo_data(insn_fifo_rd_data),
        .o_fifo_empty(insn_fifo_empty),
        .i_fifo_wr_en(insn_fifo_wr_en),
        .i_fifo_data(insn_fifo_wr_data),
        .o_fifo_full(insn_fifo_full)
    );

    dispatch #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) dispatch_inst (
        .clk(clk),
        .n_rst(SW[17]),
        .i_insn_fifo_empty(insn_fifo_empty),
        .i_insn_fifo_data(insn_fifo_rd_data),
        .o_insn_fifo_rd_en(insn_fifo_rd_en),
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
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH),
        .CDB_DEPTH(`CDB_DEPTH),
        .ROB_DEPTH(`ROB_DEPTH)
    ) rob (
        .clk(clk),
        .n_rst(SW[17]),
        .o_redirect(rob_redirect),
        .o_redirect_addr(rob_redirect_addr),
        .i_cdb_en(cdb_en),
        .i_cdb_redirect(cdb_redirect),
        .i_cdb_data(cdb_data),
        .i_cdb_addr(cdb_addr),
        .i_cdb_tag(cdb_tag),
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
        .n_rst(SW[17]),
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

    generate
    for (i = 0; i < `CDB_DEPTH; i++) begin : GENERATE_RS_IEU_UNITS
        reservation_station #(
            .DATA_WIDTH(`DATA_WIDTH),
            .ADDR_WIDTH(`ADDR_WIDTH),
            .TAG_WIDTH(`TAG_WIDTH),
            .CDB_DEPTH(`CDB_DEPTH),
            .RS_DEPTH(`RS_DEPTH)
        ) rs_inst (
            .clk(clk),
            .n_rst(SW[17]),
            .i_flush(rob_redirect),
            .i_cdb_en(cdb_en),
            .i_cdb_redirect(cdb_redirect),
            .i_cdb_data(cdb_data),
            .i_cdb_addr(cdb_addr),
            .i_cdb_tag(cdb_tag),
            .i_rs_en(rs_en_m[i]),
            .i_rs_opcode(rs_opcode),
            .i_rs_iaddr(rs_iaddr),
            .i_rs_insn(rs_insn),
            .i_rs_src_tag(rs_src_tag),
            .i_rs_src_data(rs_src_data),
            .i_rs_src_rdy(rs_src_rdy),
            .i_rs_dst_tag(rs_dst_tag),
            .o_rs_stall(rs_stall_m[i]),
            .i_fu_stall(fu_stall[i]),
            .o_fu_valid(fu_valid[i]),
            .o_fu_opcode(fu_opcode[i]),
            .o_fu_iaddr(fu_iaddr[i]),
            .o_fu_insn(fu_insn[i]),
            .o_fu_src_a(fu_src_a[i]),
            .o_fu_src_b(fu_src_b[i]),
            .o_fu_tag(fu_tag[i])
        );

        ieu #(
            .DATA_WIDTH(`DATA_WIDTH),
            .ADDR_WIDTH(`ADDR_WIDTH),
            .TAG_WIDTH(`TAG_WIDTH)
        ) ieu_inst (
            .clk(clk),
            .n_rst(SW[17]),
            .i_flush(rob_redirect),
            .o_cdb_en(cdb_en[i]),
            .o_cdb_redirect(cdb_redirect[i]),
            .o_cdb_data(cdb_data[i]),
            .o_cdb_addr(cdb_addr[i]),
            .o_cdb_tag(cdb_tag[i]),
            .i_fu_valid(fu_valid[i]),
            .i_fu_opcode(fu_opcode[i]),
            .i_fu_iaddr(fu_iaddr[i]),
            .i_fu_insn(fu_insn[i]),
            .i_fu_src_a(fu_src_a[i]),
            .i_fu_src_b(fu_src_b[i]),
            .i_fu_tag(fu_tag[i]),
            .o_fu_stall(fu_stall[i])
        );
    end
    endgenerate

endmodule
