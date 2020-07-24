/*
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Wishbone Bus Interface Unit
// This module is the interface to the Wishbone Bus
// All transactions from the CPU will go through here

// WISHBONE DATASHEET
// Description:                     RISC-V processor core master interface to a shared wishbone bus
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

module procyon_biu_wb #(
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
    localparam BIU_IDX_WIDTH        = $clog2(BIU_DATA_WIDTH / OPTN_WB_DATA_WIDTH);
    localparam BIU_STATE_WIDTH      = 3;
    localparam BIU_STATE_IDLE       = 3'b000;
    localparam BIU_STATE_SEND_REQ   = 3'b001;
    localparam BIU_STATE_RMW_READ   = 3'b010;
    localparam BIU_STATE_RMW_MODIFY = 3'b011;
    localparam BIU_STATE_RMW_WRITE  = 3'b100;
    localparam BIU_STATE_DONE       = 3'b101;
    localparam BIU_STATE_ERR        = 3'b111;

    logic [BIU_STATE_WIDTH-1:0]    biu_state_r;
    logic [BIU_STATE_WIDTH-1:0]    biu_state_next;

    logic [BIU_COUNTER_WIDTH-1:0]  req_cnt_r;
    logic [BIU_COUNTER_WIDTH-1:0]  req_cnt_next;
    logic [BIU_COUNTER_WIDTH-1:0]  initial_count;
    logic [BIU_IDX_WIDTH-1:0]      req_idx_r;
    logic [BIU_IDX_WIDTH-1:0]      req_idx_next;
    logic [OPTN_WB_DATA_WIDTH-1:0] rmw_data;
    logic                          wb_cyc_r;
    logic                          wb_stb_r;
    logic                          wb_we_r;
    logic [`WB_CTI_WIDTH-1:0]      wb_cti_r;
    logic [`WB_BTE_WIDTH-1:0]      wb_bte_r;
    logic [WB_DATA_SIZE-1:0]       wb_sel_r;
    logic [OPTN_WB_ADDR_WIDTH-1:0] wb_addr_r;
    logic [OPTN_WB_DATA_WIDTH-1:0] wb_data_r;
    logic                          biu_done_r;
    logic [BIU_DATA_WIDTH-1:0]     biu_data_r;

    // Output to wishbone bus
    assign o_wb_cyc   = wb_cyc_r;
    assign o_wb_stb   = wb_stb_r;
    assign o_wb_we    = wb_we_r;
    assign o_wb_cti   = wb_cti_r;
    assign o_wb_bte   = wb_bte_r;
    assign o_wb_sel   = wb_sel_r;
    assign o_wb_addr  = wb_addr_r;
    assign o_wb_data  = wb_data_r;

    // Output to BIU interface
    assign o_biu_done = biu_done_r;
    assign o_biu_data = biu_data_r;

    // Calculate initial counts when in IDLE state
    always_comb begin
        case (i_biu_len)
            `PCYN_BIU_LEN_1B:   initial_count = BIU_COUNTER_WIDTH'(1   / WB_DATA_SIZE);
            `PCYN_BIU_LEN_2B:   initial_count = BIU_COUNTER_WIDTH'(2   / WB_DATA_SIZE);
            `PCYN_BIU_LEN_4B:   initial_count = BIU_COUNTER_WIDTH'(4   / WB_DATA_SIZE);
            `PCYN_BIU_LEN_8B:   initial_count = BIU_COUNTER_WIDTH'(8   / WB_DATA_SIZE);
            `PCYN_BIU_LEN_16B:  initial_count = BIU_COUNTER_WIDTH'(16  / WB_DATA_SIZE);
            `PCYN_BIU_LEN_32B:  initial_count = BIU_COUNTER_WIDTH'(32  / WB_DATA_SIZE);
            `PCYN_BIU_LEN_64B:  initial_count = BIU_COUNTER_WIDTH'(64  / WB_DATA_SIZE);
            `PCYN_BIU_LEN_128B: initial_count = BIU_COUNTER_WIDTH'(128 / WB_DATA_SIZE);
            default:            initial_count = {(BIU_COUNTER_WIDTH){1'b0}};
        endcase

        // Adjust intial_count if it is 0 (i.e. the transfer size is smaller then the WB port size)
        if (initial_count == 0) initial_count = BIU_COUNTER_WIDTH'(1);
    end

    // Next state logic
    always_comb begin
        case (biu_state_r)
            BIU_STATE_IDLE:       biu_state_next = i_biu_en ? (i_biu_func == `PCYN_BIU_FUNC_RMW ? BIU_STATE_RMW_READ : BIU_STATE_SEND_REQ) : BIU_STATE_IDLE;
            BIU_STATE_SEND_REQ:   biu_state_next = req_cnt_next == 0 ? BIU_STATE_DONE : BIU_STATE_SEND_REQ;
            BIU_STATE_RMW_READ:   biu_state_next = i_wb_ack ? BIU_STATE_RMW_MODIFY : BIU_STATE_RMW_READ;
            BIU_STATE_RMW_MODIFY: biu_state_next = BIU_STATE_RMW_WRITE;
            BIU_STATE_RMW_WRITE:  biu_state_next = i_wb_ack ? (req_cnt_next == 0 ? BIU_STATE_DONE : BIU_STATE_RMW_READ) : BIU_STATE_RMW_WRITE;
            BIU_STATE_DONE:       biu_state_next = BIU_STATE_IDLE;
            default:              biu_state_next = biu_state_r;
        endcase
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) biu_state_r <= BIU_STATE_IDLE;
        else          biu_state_r <= biu_state_next;
    end

    // BIU counter and index FSM
    always_comb begin
        case (biu_state_r)
            BIU_STATE_IDLE: begin
                req_cnt_next = initial_count;
                req_idx_next = {(BIU_IDX_WIDTH){1'b0}};
            end
            BIU_STATE_SEND_REQ: begin
                req_cnt_next = i_wb_ack ? req_cnt_r - 1'b1 : req_cnt_r;
                req_idx_next = i_wb_ack ? req_idx_r + 1'b1 : req_idx_r;
            end
            BIU_STATE_RMW_WRITE: begin
                req_cnt_next = i_wb_ack ? req_cnt_r - 1'b1 : req_cnt_r;
                req_idx_next = i_wb_ack ? req_idx_r + 1'b1 : req_idx_r;
            end
            BIU_STATE_DONE: begin
                req_cnt_next = req_cnt_r;
                req_idx_next = {(BIU_IDX_WIDTH){1'b0}};
            end
            default: begin
                req_cnt_next = req_cnt_r;
                req_idx_next = req_idx_r;
            end
        endcase
    end

    always_ff @(posedge i_wb_clk) begin
        req_cnt_r <= req_cnt_next;
        req_idx_r <= req_idx_next;
    end

    // RMW data mux
    always_comb begin
        logic [WB_DATA_SIZE-1:0]       rmw_sel;
        logic [OPTN_WB_DATA_WIDTH-1:0] biu_data_rd;
        logic [OPTN_WB_DATA_WIDTH-1:0] biu_data_wr;

        rmw_sel     = i_biu_sel[req_idx_r*WB_DATA_SIZE +: WB_DATA_SIZE];
        biu_data_wr = i_biu_data[req_idx_r*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH];
        biu_data_rd = biu_data_r[req_idx_r*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH];

        for (int i = 0; i < WB_DATA_SIZE; i++) begin
            rmw_data[i*8 +: 8] = rmw_sel[i] ? biu_data_wr[i*8 +: 8] : biu_data_rd[i*8 +: 8];
        end
    end

    // BIU wishbone FSM
    always_ff @(posedge i_wb_clk) begin
        case (biu_state_r)
            BIU_STATE_IDLE: begin
                wb_cyc_r  <= i_biu_en;
                wb_stb_r  <= i_biu_en;
                wb_we_r   <= i_biu_func == `PCYN_BIU_FUNC_WRITE;
                wb_cti_r  <= (i_biu_func == `PCYN_BIU_FUNC_RMW) ? `WB_CTI_CLASSIC : (req_cnt_next == BIU_COUNTER_WIDTH'(1) ? `WB_CTI_END_OF_BURST : `WB_CTI_INCREMENTING);
                wb_bte_r  <= `WB_BTE_LINEAR;
                wb_sel_r  <= (i_biu_func == `PCYN_BIU_FUNC_RMW) ? {(WB_DATA_SIZE){1'b1}} : i_biu_sel[req_idx_next*WB_DATA_SIZE +: WB_DATA_SIZE];
                wb_addr_r <= i_biu_addr[OPTN_WB_ADDR_WIDTH-1:0];
                wb_data_r <= i_biu_data[req_idx_next*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH];
            end
            BIU_STATE_SEND_REQ: begin
                wb_cyc_r  <= req_cnt_next != 0;
                wb_stb_r  <= req_cnt_next != 0;
                wb_we_r   <= i_biu_func == `PCYN_BIU_FUNC_WRITE;
                wb_cti_r  <= req_cnt_next == BIU_COUNTER_WIDTH'(1) ? `WB_CTI_END_OF_BURST : wb_cti_r;
                wb_bte_r  <= wb_bte_r;
                wb_sel_r  <= i_biu_sel[req_idx_next*WB_DATA_SIZE +: WB_DATA_SIZE];
                wb_addr_r <= i_wb_ack ? wb_addr_r + OPTN_WB_ADDR_WIDTH'(WB_DATA_SIZE) : wb_addr_r;
                wb_data_r <= i_biu_data[req_idx_next*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH];
            end
            BIU_STATE_RMW_READ: begin
                wb_cyc_r  <= 1'b1;
                wb_stb_r  <= ~i_wb_ack;
                wb_we_r   <= 1'b0;
                wb_cti_r  <= wb_cti_r;
                wb_bte_r  <= wb_bte_r;
                wb_sel_r  <= wb_sel_r;
                wb_addr_r <= wb_addr_r;
                wb_data_r <= wb_data_r;
            end
            BIU_STATE_RMW_MODIFY: begin
                wb_cyc_r  <= 1'b1;
                wb_stb_r  <= 1'b1;
                wb_we_r   <= 1'b1;
                wb_cti_r  <= wb_cti_r;
                wb_bte_r  <= wb_bte_r;
                wb_sel_r  <= wb_sel_r;
                wb_addr_r <= wb_addr_r;
                wb_data_r <= rmw_data;
            end
            BIU_STATE_RMW_WRITE: begin
                wb_cyc_r  <= req_cnt_next != 0;
                wb_stb_r  <= req_cnt_next != 0;
                wb_we_r   <= ~i_wb_ack;
                wb_cti_r  <= wb_cti_r;
                wb_bte_r  <= wb_bte_r;
                wb_sel_r  <= wb_sel_r;
                wb_addr_r <= i_wb_ack ? wb_addr_r + OPTN_WB_ADDR_WIDTH'(WB_DATA_SIZE) : wb_addr_r;
                wb_data_r <= wb_data_r;
            end
            BIU_STATE_DONE: begin
                wb_cyc_r  <= 1'b0;
                wb_stb_r  <= 1'b0;
                wb_we_r   <= 1'b0;
                wb_cti_r  <= wb_cti_r;
                wb_bte_r  <= wb_bte_r;
                wb_sel_r  <= wb_sel_r;
                wb_addr_r <= wb_addr_r;
                wb_data_r <= wb_data_r;
            end
            default: begin
                wb_cyc_r  <= 1'b0;
                wb_stb_r  <= 1'b0;
                wb_we_r   <= 1'b0;
                wb_cti_r  <= wb_cti_r;
                wb_bte_r  <= wb_bte_r;
                wb_sel_r  <= wb_sel_r;
                wb_addr_r <= wb_addr_r;
                wb_data_r <= wb_data_r;
            end
        endcase
    end

    // BIU interface FSM
    always_ff @(posedge i_wb_clk) begin
        case (biu_state_r)
            BIU_STATE_IDLE: begin
                biu_done_r <= 1'b0;
                biu_data_r <= {(BIU_DATA_WIDTH){1'b0}};
            end
            BIU_STATE_SEND_REQ: begin
                biu_done_r <= req_cnt_next == 0;
                biu_data_r[req_idx_r*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH] <= i_wb_data;
            end
            BIU_STATE_RMW_READ: begin
                biu_done_r <= 1'b0;
                biu_data_r[req_idx_r*OPTN_WB_DATA_WIDTH +: OPTN_WB_DATA_WIDTH] <= i_wb_data;
            end
            BIU_STATE_RMW_MODIFY: begin
                biu_done_r <= 1'b0;
                biu_data_r <= biu_data_r;
            end
            BIU_STATE_RMW_WRITE: begin
                biu_done_r <= req_cnt_next == 0;
                biu_data_r <= biu_data_r;
            end
            BIU_STATE_DONE: begin
                biu_done_r <= 1'b0;
                biu_data_r <= biu_data_r;
            end
            default: begin
                biu_done_r <= 1'b0;
                biu_data_r <= biu_data_r;
            end
        endcase
    end

endmodule
