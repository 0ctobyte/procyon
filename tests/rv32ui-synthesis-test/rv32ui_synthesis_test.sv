`timescale 1ns/1ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 32
`define TAG_WIDTH  6
`define REG_ADDR_WIDTH 5

`define ROM_DEPTH 512
`define REGMAP_DEPTH 32
`define ROB_DEPTH 64
`define RS_DEPTH 8

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
        .TAG_WIDTH(`TAG_WIDTH),
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

    logic [6:0] o_hex [0:7];

    assign key = ~KEY[0];

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
                RUN:  state <= regmap_dest_wr.wr_en ? HALT : RUN;
                HALT: state <= key_pulse ? RUN : HALT;
            endcase
        end
    end

    always_comb begin
        logic [`ADDR_WIDTH-1:0] t;
        t = fetch_pc >> 2;
        rom_rd_addr = t[$clog2(`ROM_DEPTH)-1:0];
    end

    genvar i;
    generate
    for (i = 0; i < 8; i++) begin : SEG7_DECODER_INSTANCES
        seg7_decoder seg7_decoder_inst (
            .n_rst(SW[17]),
            .i_hex(regmap_dest_wr.data[i*4+3:i*4]),
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
        .i_rd_addr(rom_rd_addr),
        .o_data_out(rom_data_out)
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
        .insn_fifo_wr(insn_fifo_wr)
    );

    sync_fifo #(
        .DATA_WIDTH(`ADDR_WIDTH+`DATA_WIDTH),
        .FIFO_DEPTH(8)
    ) insn_fifo (
        .clk(clk),
        .n_rst(SW[17]),
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
        .n_rst(SW[17]),
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
        .n_rst(SW[17]),
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
        .n_rst(SW[17]),
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
        .n_rst(SW[17]),
        .i_flush(rob_redirect),
        .cdb(cdb),
        .rs_dispatch(rs_dispatch),
        .rs_funit(rs_funit)
    );

    ieu #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH)
    ) ieu_inst (
        .clk(clk),
        .n_rst(SW[17]),
        .i_flush(rob_redirect),
        .cdb(cdb),
        .rs_funit(rs_funit)
    );

endmodule
