/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

`include "../../rtl/lib/procyon_biu_wb_constants.svh"

module boot_ctrl #(
    parameter OPTN_WB_DATA_WIDTH = 32,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_HEX_SIZE      = 32,
    parameter OPTN_IC_LINE_SIZE  = 32,

    parameter IC_LINE_WIDTH      = OPTN_IC_LINE_SIZE * 8,
    parameter WB_DATA_SIZE       = OPTN_WB_DATA_WIDTH / 8,
    parameter ROM_ADDR_WIDTH     = OPTN_HEX_SIZE == 1 ? 1 : $clog2(OPTN_HEX_SIZE)
)(
    // Wishbone interface
    input  logic                            i_wb_clk,
    input  logic                            i_wb_rst,
    input  logic                            i_wb_ack,
    input  logic [OPTN_WB_DATA_WIDTH-1:0]   i_wb_data,
    output logic                            o_wb_cyc,
    output logic                            o_wb_stb,
    output logic                            o_wb_we,
    output logic [`WB_CTI_WIDTH-1:0]        o_wb_cti,
    output logic [`WB_BTE_WIDTH-1:0]        o_wb_bte,
    output logic [WB_DATA_SIZE-1:0]         o_wb_sel,
    output logic [OPTN_WB_ADDR_WIDTH-1:0]   o_wb_addr,
    output logic [OPTN_WB_DATA_WIDTH-1:0]   o_wb_data,

    // ROM interface
    input  logic [IC_LINE_WIDTH-1:0]        i_rom_data,
    output logic [ROM_ADDR_WIDTH-1:0]       o_rom_addr,

    output logic                            o_boot_ctrl_done
);

    localparam IC_OFFSET_WIDTH = $clog2(OPTN_IC_LINE_SIZE);
    localparam BOOT_CTRL_STATE_WIDTH = 2;
    localparam BOOT_CTRL_STATE_RESET = 2'b00;
    localparam BOOT_CTRL_STATE_BUSY  = 2'b01;
    localparam BOOT_CTRL_STATE_DONE  = 2'b10;

    logic n_wb_rst;
    assign n_wb_rst = ~i_wb_rst;

    logic biu_en_next;
    logic biu_en_r;
    logic [`PCYN_BIU_FUNC_WIDTH-1:0] biu_func;
    logic [`PCYN_BIU_LEN_WIDTH-1:0] biu_len;
    logic [OPTN_IC_LINE_SIZE-1:0] biu_sel;
    logic [OPTN_WB_ADDR_WIDTH-1:0] biu_addr;
    logic [IC_LINE_WIDTH-1:0] biu_data_o_next;
    logic [IC_LINE_WIDTH-1:0] biu_data_o_r;
    logic biu_done;
/* verilator lint_off UNUSED */
    logic [IC_LINE_WIDTH-1:0] biu_data_i;
/* verilator lint_on  UNUSED */

    assign biu_func = `PCYN_BIU_FUNC_WRITE;
    assign biu_sel = '1;

    generate
    case (OPTN_IC_LINE_SIZE)
        4:       assign biu_len = `PCYN_BIU_LEN_4B;
        8:       assign biu_len = `PCYN_BIU_LEN_8B;
        16:      assign biu_len = `PCYN_BIU_LEN_16B;
        32:      assign biu_len = `PCYN_BIU_LEN_32B;
        64:      assign biu_len = `PCYN_BIU_LEN_64B;
        128:     assign biu_len = `PCYN_BIU_LEN_128B;
        default: assign biu_len = `PCYN_BIU_LEN_4B;
    endcase
    endgenerate

    logic [ROM_ADDR_WIDTH-1:0] rom_addr_next;
    logic [ROM_ADDR_WIDTH-1:0] rom_addr_r;
    logic [BOOT_CTRL_STATE_WIDTH-1:0] boot_ctrl_state_next;
    logic [BOOT_CTRL_STATE_WIDTH-1:0] boot_ctrl_state_r;

    always_comb begin
        biu_data_o_next = i_rom_data;
        biu_addr = {{(OPTN_WB_ADDR_WIDTH-ROM_ADDR_WIDTH-IC_OFFSET_WIDTH){1'b0}}, rom_addr_r, {(IC_OFFSET_WIDTH){1'b0}}};

        case (boot_ctrl_state_r)
            BOOT_CTRL_STATE_RESET: begin
                biu_en_next = 1'b0;
                rom_addr_next = '0;
                boot_ctrl_state_next = BOOT_CTRL_STATE_BUSY;
            end
            BOOT_CTRL_STATE_BUSY: begin
                biu_en_next = ~biu_done;
                rom_addr_next = rom_addr_r + (ROM_ADDR_WIDTH)'(biu_done);
                boot_ctrl_state_next = ((rom_addr_r == (ROM_ADDR_WIDTH)'(OPTN_HEX_SIZE-1)) & biu_done) ? BOOT_CTRL_STATE_DONE : BOOT_CTRL_STATE_BUSY;
            end
            BOOT_CTRL_STATE_DONE: begin
                biu_en_next = 1'b0;
                rom_addr_next = '0;
                boot_ctrl_state_next = BOOT_CTRL_STATE_DONE;
            end
            default: begin
                biu_en_next = 1'b0;
                rom_addr_next = '0;
                boot_ctrl_state_next = BOOT_CTRL_STATE_DONE;
            end
        endcase
    end

    procyon_srff #(BOOT_CTRL_STATE_WIDTH) boot_ctrl_state_r_srff (.clk(i_wb_clk), .n_rst(n_wb_rst), .i_en(1'b1), .i_set(boot_ctrl_state_next), .i_reset(BOOT_CTRL_STATE_RESET), .o_q(boot_ctrl_state_r));
    procyon_srff #(1) biu_en_r_srff (.clk(i_wb_clk), .n_rst(n_wb_rst), .i_en(1'b1), .i_set(biu_en_next), .i_reset(1'b0), .o_q(biu_en_r));
    procyon_ff #(ROM_ADDR_WIDTH) rom_addr_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(rom_addr_next), .o_q(rom_addr_r));
    procyon_ff #(IC_LINE_WIDTH) biu_data_o_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(biu_data_o_next), .o_q(biu_data_o_r));

    procyon_biu_controller_wb #(
        .OPTN_BIU_DATA_SIZE(OPTN_IC_LINE_SIZE),
        .OPTN_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH)
    ) procyon_biu_controller_wb_inst (
        .i_biu_en(biu_en_r),
        .i_biu_func(biu_func),
        .i_biu_len(biu_len),
        .i_biu_sel(biu_sel),
        .i_biu_addr(biu_addr),
        .i_biu_data(biu_data_o_r),
        .o_biu_done(biu_done),
        .o_biu_data(biu_data_i),
        .i_wb_clk(i_wb_clk),
        .i_wb_rst(i_wb_rst),
        .i_wb_ack(i_wb_ack),
        .i_wb_data(i_wb_data),
        .o_wb_cyc(o_wb_cyc),
        .o_wb_stb(o_wb_stb),
        .o_wb_we(o_wb_we),
        .o_wb_cti(o_wb_cti),
        .o_wb_bte(o_wb_bte),
        .o_wb_sel(o_wb_sel),
        .o_wb_addr(o_wb_addr),
        .o_wb_data(o_wb_data)
    );

    assign o_boot_ctrl_done = boot_ctrl_state_r[1];
    assign o_rom_addr = rom_addr_r;

endmodule