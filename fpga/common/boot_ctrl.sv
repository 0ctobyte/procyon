/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module boot_ctrl #(
    parameter OPTN_WB_DATA_WIDTH = 32,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_HEX_SIZE      = 32,
    parameter OPTN_IC_LINE_SIZE  = 32
)(
    // Wishbone interface
    input  logic                                     i_wb_clk,
    input  logic                                     i_wb_rst,
    input  logic                                     i_wb_ack,
    input  logic [OPTN_WB_DATA_WIDTH-1:0]            i_wb_data,
    output logic                                     o_wb_cyc,
    output logic                                     o_wb_stb,
    output logic                                     o_wb_we,
    output wb_cti_t                                  o_wb_cti,
    output wb_bte_t                                  o_wb_bte,
    output logic [`PCYN_W2S(OPTN_WB_DATA_WIDTH)-1:0] o_wb_sel,
    output logic [OPTN_WB_ADDR_WIDTH-1:0]            o_wb_addr,
    output logic [OPTN_WB_DATA_WIDTH-1:0]            o_wb_data,

    // ROM interface
    input  logic [`PCYN_S2W(OPTN_IC_LINE_SIZE)-1:0]  i_rom_data,
    output logic [`PCYN_C2I(OPTN_HEX_SIZE)-1:0]      o_rom_addr,

    output logic                                     o_boot_ctrl_done
);

    localparam IC_LINE_WIDTH = `PCYN_S2W(OPTN_IC_LINE_SIZE);
    localparam WB_DATA_SIZE = `PCYN_W2S(OPTN_WB_DATA_WIDTH);
    localparam ROM_ADDR_WIDTH = `PCYN_C2I(OPTN_HEX_SIZE);
    localparam IC_OFFSET_WIDTH = $clog2(OPTN_IC_LINE_SIZE);
    localparam BOOT_CTRL_STATE_WIDTH = 2;

    typedef enum logic [BOOT_CTRL_STATE_WIDTH-1:0] {
        BOOT_CTRL_STATE_RESET = BOOT_CTRL_STATE_WIDTH'('b00),
        BOOT_CTRL_STATE_BUSY  = BOOT_CTRL_STATE_WIDTH'('b01),
        BOOT_CTRL_STATE_DONE  = BOOT_CTRL_STATE_WIDTH'('b10)
    } boot_ctrl_state_t;

    logic n_wb_rst;
    assign n_wb_rst = ~i_wb_rst;

    logic biu_en_next;
    logic biu_en_r;
    pcyn_biu_func_t biu_func;
    pcyn_biu_len_t biu_len;
    logic [OPTN_IC_LINE_SIZE-1:0] biu_sel;
    logic [OPTN_WB_ADDR_WIDTH-1:0] biu_addr;
    logic [IC_LINE_WIDTH-1:0] biu_data_o_next;
    logic [IC_LINE_WIDTH-1:0] biu_data_o_r;
    logic biu_done;
/* verilator lint_off UNUSED */
    logic [IC_LINE_WIDTH-1:0] biu_data_i;
/* verilator lint_on  UNUSED */

    assign biu_func = PCYN_BIU_FUNC_WRITE;
    assign biu_sel = '1;

    generate
    case (OPTN_IC_LINE_SIZE)
        4:       assign biu_len = PCYN_BIU_LEN_4B;
        8:       assign biu_len = PCYN_BIU_LEN_8B;
        16:      assign biu_len = PCYN_BIU_LEN_16B;
        32:      assign biu_len = PCYN_BIU_LEN_32B;
        64:      assign biu_len = PCYN_BIU_LEN_64B;
        128:     assign biu_len = PCYN_BIU_LEN_128B;
        default: assign biu_len = PCYN_BIU_LEN_4B;
    endcase
    endgenerate

    boot_ctrl_state_t boot_ctrl_state_next;
    boot_ctrl_state_t boot_ctrl_state_r;

    always_comb begin
        unique case (boot_ctrl_state_r)
            BOOT_CTRL_STATE_RESET: boot_ctrl_state_next = BOOT_CTRL_STATE_BUSY;
            BOOT_CTRL_STATE_BUSY:  boot_ctrl_state_next = ((rom_addr_r == ROM_ADDR_WIDTH'(OPTN_HEX_SIZE-1)) & biu_done) ? BOOT_CTRL_STATE_DONE : BOOT_CTRL_STATE_BUSY;
            BOOT_CTRL_STATE_DONE:  boot_ctrl_state_next = BOOT_CTRL_STATE_DONE;
            default:               boot_ctrl_state_next = BOOT_CTRL_STATE_DONE;
        endcase
    end

    procyon_srff #(BOOT_CTRL_STATE_WIDTH) boot_ctrl_state_r_srff (.clk(i_wb_clk), .n_rst(n_wb_rst), .i_en(1'b1), .i_set(boot_ctrl_state_next), .i_reset(BOOT_CTRL_STATE_RESET), .o_q(boot_ctrl_state_r));

    logic [ROM_ADDR_WIDTH-1:0] rom_addr_next;
    logic [ROM_ADDR_WIDTH-1:0] rom_addr_r;

    always_comb begin
        biu_data_o_next = i_rom_data;
        biu_addr = {{(OPTN_WB_ADDR_WIDTH-ROM_ADDR_WIDTH-IC_OFFSET_WIDTH){1'b0}}, rom_addr_r, IC_OFFSET_WIDTH'(0)};

        unique case (boot_ctrl_state_r)
            BOOT_CTRL_STATE_RESET: begin
                biu_en_next = 1'b0;
                rom_addr_next = '0;
            end
            BOOT_CTRL_STATE_BUSY: begin
                biu_en_next = ~biu_done;
                rom_addr_next = rom_addr_r + ROM_ADDR_WIDTH'(biu_done);
            end
            BOOT_CTRL_STATE_DONE: begin
                biu_en_next = 1'b0;
                rom_addr_next = '0;
            end
            default: begin
                biu_en_next = 1'b0;
                rom_addr_next = '0;
            end
        endcase
    end

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
