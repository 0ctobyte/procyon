/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Wishbone Bus Interface Unit Controller
// This module is the interface to the Wishbone Bus. It can send read/write requests but does not receive requests.

// WISHBONE DATASHEET
// Description:                     Wishbone interface controller
// Wishbone rev:                    B4
// Supported Cycles:                Register feedback burst read/write, Read-Modify-Write
// CTI support:                     Classic, Incrementing Burst, End of Burst
// BTE support:                     Linear only
// Data port size:                  parameterized: 8-bit, 16-bit, 32-bit, 64-bit supported
// Data port granularity:           8-bit
// Data port max operand size:      8-bit
// Data ordering:                   Little Endian
// Data sequence:                   Undefined
// Clock constraints:               None
// Wishbone signals mapping:
// i_wb_clk   -> CLK_I
// i_wb_rst   -> RST_I
// i_wb_ack   -> ACK_I
// i_wb_data  -> DAT_I()
// o_wb_cyc   -> CYC_O
// o_wb_stb   -> STB_O
// o_wb_we    -> WE_O
// o_wb_cti   -> CTI_O()
// o_wb_bte   -> BTE_O()
// o_wb_sel   -> SEL_O()
// o_wb_addr  -> ADR_O()
// o_wb_data  -> DAT_O()

`include "procyon_biu_wb_constants.svh"

module procyon_biu_controller_wb #(
    parameter OPTN_BIU_DATA_SIZE = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_WB_DATA_WIDTH = 16,
    parameter OPTN_WB_ADDR_WIDTH = 32,

    parameter BIU_DATA_WIDTH     = OPTN_BIU_DATA_SIZE * 8,
    parameter WB_DATA_SIZE       = OPTN_WB_DATA_WIDTH / 8
)(
    // BIU request interface
    input  logic                            i_biu_en,
    input  logic [`PCYN_BIU_FUNC_WIDTH-1:0] i_biu_func,
    input  logic [`PCYN_BIU_LEN_WIDTH-1:0]  i_biu_len,
    input  logic [OPTN_BIU_DATA_SIZE-1:0]   i_biu_sel,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_biu_addr,
    input  logic [BIU_DATA_WIDTH-1:0]       i_biu_data,
    output logic                            o_biu_done,
    output logic [BIU_DATA_WIDTH-1:0]       o_biu_data,

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
    output logic [OPTN_WB_DATA_WIDTH-1:0]   o_wb_data
);

    localparam BIU_COUNTER_WIDTH    = $clog2(`PCYN_BIU_LEN_MAX_SIZE / WB_DATA_SIZE);
    localparam BIU_IDX_WIDTH        = BIU_DATA_WIDTH == OPTN_WB_DATA_WIDTH ? 1 : $clog2(BIU_DATA_WIDTH / OPTN_WB_DATA_WIDTH);
    localparam BIU_STATE_WIDTH      = 3;
    localparam BIU_STATE_IDLE       = 3'b000;
    localparam BIU_STATE_SEND_REQ   = 3'b001;
    localparam BIU_STATE_RMW_READ   = 3'b010;
    localparam BIU_STATE_RMW_MODIFY = 3'b011;
    localparam BIU_STATE_RMW_WRITE  = 3'b100;
    localparam BIU_STATE_DONE       = 3'b101;
    localparam BIU_STATE_ERR        = 3'b111;

    logic n_wb_rst;
    assign n_wb_rst = ~i_wb_rst;

    // Calculate initial counts when in IDLE state
    logic [BIU_COUNTER_WIDTH-1:0] initial_count;
    always_comb begin
        case (i_biu_len)
            `PCYN_BIU_LEN_1B:   initial_count = BIU_COUNTER_WIDTH'(1 / WB_DATA_SIZE);
            `PCYN_BIU_LEN_2B:   initial_count = BIU_COUNTER_WIDTH'(2 / WB_DATA_SIZE);
            `PCYN_BIU_LEN_4B:   initial_count = BIU_COUNTER_WIDTH'(4 / WB_DATA_SIZE);
            `PCYN_BIU_LEN_8B:   initial_count = BIU_COUNTER_WIDTH'(8 / WB_DATA_SIZE);
            `PCYN_BIU_LEN_16B:  initial_count = BIU_COUNTER_WIDTH'(16 / WB_DATA_SIZE);
            `PCYN_BIU_LEN_32B:  initial_count = BIU_COUNTER_WIDTH'(32 / WB_DATA_SIZE);
            `PCYN_BIU_LEN_64B:  initial_count = BIU_COUNTER_WIDTH'(64 / WB_DATA_SIZE);
            `PCYN_BIU_LEN_128B: initial_count = BIU_COUNTER_WIDTH'(128 / WB_DATA_SIZE);
            default:            initial_count = '0;
        endcase

        // Adjust intial_count if it is 0 (i.e. the transfer size is smaller then the WB port size)
        if (initial_count == 0) initial_count = BIU_COUNTER_WIDTH'(1);
    end

    logic [BIU_STATE_WIDTH-1:0] biu_state_r;
    logic [BIU_STATE_WIDTH-1:0] biu_state_next;
    logic [BIU_COUNTER_WIDTH-1:0] req_cnt_r;
    logic [BIU_COUNTER_WIDTH-1:0] req_cnt_next;
    logic [BIU_IDX_WIDTH-1:0] req_idx_r;
    logic [BIU_IDX_WIDTH-1:0] req_idx_next;
    logic biu_done_r;
    logic biu_done_next;
    logic [BIU_DATA_WIDTH-1:0] biu_data_r;
    logic [BIU_DATA_WIDTH-1:0] biu_data_next;
    logic wb_cyc_r;
    logic wb_cyc_next;
    logic wb_stb_r;
    logic wb_stb_next;
    logic wb_we_r;
    logic wb_we_next;
    logic [`WB_CTI_WIDTH-1:0] wb_cti_r;
    logic [`WB_CTI_WIDTH-1:0] wb_cti_next;
    logic [`WB_BTE_WIDTH-1:0] wb_bte_r;
    logic [`WB_BTE_WIDTH-1:0] wb_bte_next;
    logic [WB_DATA_SIZE-1:0] wb_sel_r;
    logic [WB_DATA_SIZE-1:0] wb_sel_next;
    logic [OPTN_WB_ADDR_WIDTH-1:0] wb_addr_r;
    logic [OPTN_WB_ADDR_WIDTH-1:0] wb_addr_next;
    logic [OPTN_WB_DATA_WIDTH-1:0] wb_data_r;
    logic [OPTN_WB_DATA_WIDTH-1:0] wb_data_next;

    // RMW data mux
    logic [OPTN_WB_DATA_WIDTH-1:0] rmw_data;

    always_comb begin
        logic [WB_DATA_SIZE-1:0] rmw_sel;
        logic [OPTN_WB_DATA_WIDTH-1:0] biu_data_rd;
        logic [OPTN_WB_DATA_WIDTH-1:0] biu_data_wr;

        rmw_sel = i_biu_sel[req_idx_r*WB_DATA_SIZE +: WB_DATA_SIZE];
        biu_data_wr = i_biu_data[req_idx_r*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH];
        biu_data_rd = biu_data_r[req_idx_r*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH];

        for (int i = 0; i < WB_DATA_SIZE; i++) begin
            rmw_data[i*8 +: 8] = rmw_sel[i] ? biu_data_wr[i*8 +: 8] : biu_data_rd[i*8 +: 8];
        end
    end

    // BIU FSM
    always_comb begin
        biu_data_next = biu_data_r;

        case (biu_state_r)
            BIU_STATE_IDLE: begin
                req_cnt_next = initial_count;
                req_idx_next = '0;
                biu_data_next = '0;
                biu_done_next = '0;
                wb_cyc_next = i_biu_en;
                wb_stb_next = i_biu_en;
                wb_we_next = i_biu_func == `PCYN_BIU_FUNC_WRITE;
                wb_cti_next = (i_biu_func == `PCYN_BIU_FUNC_RMW) ? `WB_CTI_CLASSIC : (req_cnt_next == BIU_COUNTER_WIDTH'(1) ? `WB_CTI_END_OF_BURST : `WB_CTI_INCREMENTING);
                wb_bte_next = `WB_BTE_LINEAR;
                wb_sel_next = (i_biu_func == `PCYN_BIU_FUNC_RMW) ? (WB_DATA_SIZE)'(1) : i_biu_sel[req_idx_next*WB_DATA_SIZE +: WB_DATA_SIZE];
                wb_addr_next = i_biu_addr[OPTN_WB_ADDR_WIDTH-1:0];
                wb_data_next = i_biu_data[req_idx_next*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH];

                biu_state_next = i_biu_en ? (i_biu_func == `PCYN_BIU_FUNC_RMW ? BIU_STATE_RMW_READ : BIU_STATE_SEND_REQ) : BIU_STATE_IDLE;
            end
            BIU_STATE_SEND_REQ: begin
                req_cnt_next = i_wb_ack ? req_cnt_r - 1'b1 : req_cnt_r;
                req_idx_next = i_wb_ack ? req_idx_r + 1'b1 : req_idx_r;
                biu_data_next[req_idx_r*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH] = i_wb_data;
                biu_done_next = (req_cnt_next == 0);
                wb_cyc_next = (req_cnt_next != 0);
                wb_stb_next = (req_cnt_next != 0);
                wb_we_next = (i_biu_func == `PCYN_BIU_FUNC_WRITE);
                wb_cti_next = (req_cnt_next == BIU_COUNTER_WIDTH'(1)) ? `WB_CTI_END_OF_BURST : wb_cti_r;
                wb_bte_next = wb_bte_r;
                wb_sel_next = i_biu_sel[req_idx_next*WB_DATA_SIZE +: WB_DATA_SIZE];
                wb_addr_next = i_wb_ack ? wb_addr_r + OPTN_WB_ADDR_WIDTH'(WB_DATA_SIZE) : wb_addr_r;
                wb_data_next = i_biu_data[req_idx_next*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH];

                biu_state_next = (req_cnt_next == 0) ? BIU_STATE_DONE : BIU_STATE_SEND_REQ;
            end
            BIU_STATE_RMW_READ: begin
                req_cnt_next = req_cnt_r;
                req_idx_next = req_idx_r;
                biu_data_next[req_idx_r*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH] = i_wb_data;
                biu_done_next = 1'b0;
                wb_cyc_next = 1'b1;
                wb_stb_next = ~i_wb_ack;
                wb_we_next = 1'b0;
                wb_cti_next = wb_cti_r;
                wb_bte_next = wb_bte_r;
                wb_sel_next = wb_sel_r;
                wb_addr_next = wb_addr_r;
                wb_data_next = wb_data_r;

                biu_state_next = i_wb_ack ? BIU_STATE_RMW_MODIFY : BIU_STATE_RMW_READ;
            end
            BIU_STATE_RMW_MODIFY: begin
                req_cnt_next = req_cnt_r;
                req_idx_next = req_idx_r;
                biu_data_next = biu_data_r;
                biu_done_next = 1'b0;
                wb_cyc_next = 1'b1;
                wb_stb_next = 1'b1;
                wb_we_next = 1'b1;
                wb_cti_next = wb_cti_r;
                wb_bte_next = wb_bte_r;
                wb_sel_next = wb_sel_r;
                wb_addr_next = wb_addr_r;
                wb_data_next = rmw_data;

                biu_state_next = BIU_STATE_RMW_WRITE;
            end
            BIU_STATE_RMW_WRITE: begin
                req_cnt_next = i_wb_ack ? req_cnt_r - 1'b1 : req_cnt_r;
                req_idx_next = i_wb_ack ? req_idx_r + 1'b1 : req_idx_r;
                biu_data_next = biu_data_r;
                biu_done_next = (req_cnt_next == 0);
                wb_cyc_next = (req_cnt_next != 0);
                wb_stb_next = (req_cnt_next != 0);
                wb_we_next = ~i_wb_ack;
                wb_cti_next = wb_cti_r;
                wb_bte_next = wb_bte_r;
                wb_sel_next = wb_sel_r;
                wb_addr_next = i_wb_ack ? wb_addr_r + OPTN_WB_ADDR_WIDTH'(WB_DATA_SIZE) : wb_addr_r;
                wb_data_next = wb_data_r;

                biu_state_next = i_wb_ack ? (req_cnt_next == 0 ? BIU_STATE_DONE : BIU_STATE_RMW_READ) : BIU_STATE_RMW_WRITE;
            end
            BIU_STATE_DONE: begin
                req_cnt_next = req_cnt_r;
                req_idx_next = '0;
                biu_data_next = biu_data_r;
                biu_done_next = 1'b0;
                wb_cyc_next = 1'b0;
                wb_stb_next = 1'b0;
                wb_we_next = 1'b0;
                wb_cti_next = wb_cti_r;
                wb_bte_next = wb_bte_r;
                wb_sel_next = wb_sel_r;
                wb_addr_next = wb_addr_r;
                wb_data_next = wb_data_r;

                biu_state_next = BIU_STATE_IDLE;
            end
            default: begin
                req_cnt_next = req_cnt_r;
                req_idx_next = '0;
                biu_data_next = biu_data_r;
                biu_done_next = 1'b0;
                wb_cyc_next = 1'b0;
                wb_stb_next = 1'b0;
                wb_we_next = 1'b0;
                wb_cti_next = wb_cti_r;
                wb_bte_next = wb_bte_r;
                wb_sel_next = wb_sel_r;
                wb_addr_next = wb_addr_r;
                wb_data_next = wb_data_r;

                biu_state_next = biu_state_r;
            end
        endcase
    end

    procyon_ff #(BIU_COUNTER_WIDTH) req_cnt_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(req_cnt_next), .o_q(req_cnt_r));
    procyon_ff #(BIU_IDX_WIDTH) req_idx_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(req_idx_next), .o_q(req_idx_r));
    procyon_srff #(BIU_STATE_WIDTH) biu_state_r_srff (.clk(i_wb_clk), .n_rst(n_wb_rst), .i_en(1'b1), .i_set(biu_state_next), .i_reset(BIU_STATE_IDLE), .o_q(biu_state_r));
    procyon_ff #(1) biu_done_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(biu_done_next), .o_q(biu_done_r));
    procyon_ff #(BIU_DATA_WIDTH) biu_data_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(biu_data_next), .o_q(biu_data_r));
    procyon_ff #(1) wb_cyc_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(wb_cyc_next), .o_q(wb_cyc_r));
    procyon_ff #(1) wb_stb_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(wb_stb_next), .o_q(wb_stb_r));
    procyon_ff #(1) wb_we_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(wb_we_next), .o_q(wb_we_r));
    procyon_ff #(`WB_CTI_WIDTH) wb_cti_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(wb_cti_next), .o_q(wb_cti_r));
    procyon_ff #(`WB_BTE_WIDTH) wb_bte_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(wb_bte_next), .o_q(wb_bte_r));
    procyon_ff #(WB_DATA_SIZE) wb_sel_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(wb_sel_next), .o_q(wb_sel_r));
    procyon_ff #(OPTN_WB_ADDR_WIDTH) wb_addr_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(wb_addr_next), .o_q(wb_addr_r));
    procyon_ff #(OPTN_WB_DATA_WIDTH) wb_data_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(wb_data_next), .o_q(wb_data_r));

    // Output to wishbone bus
    assign o_wb_cyc = wb_cyc_r;
    assign o_wb_stb = wb_stb_r;
    assign o_wb_we = wb_we_r;
    assign o_wb_cti = wb_cti_r;
    assign o_wb_bte = wb_bte_r;
    assign o_wb_sel = wb_sel_r;
    assign o_wb_addr = wb_addr_r;
    assign o_wb_data = wb_data_r;

    // Output to BIU interface
    assign o_biu_done = biu_done_r;
    assign o_biu_data = biu_data_r;

endmodule
