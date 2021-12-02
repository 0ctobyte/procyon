/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// SRAM controller with a wishbone interface
// Controls the IS61WV102416BLL SRAM chip

// Constants
`define SRAM_DATA_WIDTH 16
`define SRAM_ADDR_WIDTH 20
`define SRAM_DATA_SIZE  `SRAM_DATA_WIDTH / 8
`define SRAM_ADDR_SPAN  2097152 // 2M bytes, or 1M 2-byte words

`include "../lib/procyon_biu_wb_constants.svh"

module sram_wb #(
    parameter OPTN_WB_DATA_WIDTH = 16,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_BASE_ADDR     = 0,

    parameter WB_DATA_SIZE       = OPTN_WB_DATA_WIDTH / 8
)(
    // Wishbone Interface
    input       logic                            i_wb_clk,
    input       logic                            i_wb_rst,
    input       logic                            i_wb_cyc,
    input       logic                            i_wb_stb,
    input       logic                            i_wb_we,
    input       logic [`WB_CTI_WIDTH-1:0]        i_wb_cti,
/* verilator lint_off UNUSED */
    input       logic [`WB_BTE_WIDTH-1:0]        i_wb_bte,
/* verilator lint_on  UNUSED */
    input       logic [WB_DATA_SIZE-1:0]         i_wb_sel,
/* verilator lint_off UNUSED */
    input       logic [OPTN_WB_ADDR_WIDTH-1:0]   i_wb_addr,
/* verilator lint_on  UNUSED */
    input       logic [OPTN_WB_DATA_WIDTH-1:0]   i_wb_data,
    output      logic [OPTN_WB_DATA_WIDTH-1:0]   o_wb_data,
    output      logic                            o_wb_ack,

    // SRAM interface
    output      logic                            o_sram_ce_n,
    output      logic                            o_sram_oe_n,
    output      logic                            o_sram_we_n,
    output      logic                            o_sram_lb_n,
    output      logic                            o_sram_ub_n,
    output      logic [`SRAM_ADDR_WIDTH-1:0]     o_sram_addr,
    inout  wire logic [`SRAM_DATA_WIDTH-1:0]     io_sram_dq
);

    localparam GATHER_COUNT	           = OPTN_WB_DATA_WIDTH / `SRAM_DATA_WIDTH;
    localparam INITIAL_GATHER_COUNT    = GATHER_COUNT - 1;
    localparam GATHER_COUNT_WIDTH      = GATHER_COUNT == 1 ? 1 : $clog2(GATHER_COUNT);
    localparam SRAM_STATE_WIDTH        = 3;
    localparam SRAM_STATE_IDLE         = 3'b000;
    localparam SRAM_STATE_READ_ACK     = 3'b001;
    localparam SRAM_STATE_WRITE_ACK    = 3'b010;
    localparam SRAM_STATE_READ_GATHER  = 3'b011;
    localparam SRAM_STATE_WRITE_GATHER = 3'b100;
    localparam SRAM_STATE_UNALIGNED    = 3'b101;

    logic biu_done_r;
    logic [OPTN_WB_DATA_WIDTH-1:0] biu_data_o_r;
    logic biu_en;
    logic biu_we;
    logic biu_eob;
    logic [WB_DATA_SIZE-1:0] biu_sel;
/* verilator lint_off UNUSED */
    logic [OPTN_WB_ADDR_WIDTH-1:0] biu_addr;
/* verilator lint_on  UNUSED */
    logic [OPTN_WB_DATA_WIDTH-1:0] biu_data_i;

    procyon_biu_responder_wb #(
        .OPTN_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_BASE_ADDR(OPTN_BASE_ADDR)
    ) procyon_biu_responder_wb_inst (
        .i_wb_clk(i_wb_clk),
        .i_wb_rst(i_wb_rst),
        .i_wb_cyc(i_wb_cyc),
        .i_wb_stb(i_wb_stb),
        .i_wb_we(i_wb_we),
        .i_wb_cti(i_wb_cti),
        .i_wb_bte(i_wb_bte),
        .i_wb_sel(i_wb_sel),
        .i_wb_addr(i_wb_addr),
        .i_wb_data(i_wb_data),
        .o_wb_data(o_wb_data),
        .o_wb_ack(o_wb_ack),
        .i_biu_done(biu_done_r),
        .i_biu_data(biu_data_o_r),
        .o_biu_en(biu_en),
        .o_biu_we(biu_we),
        .o_biu_eob(biu_eob),
        .o_biu_sel(biu_sel),
        .o_biu_addr(biu_addr),
        .o_biu_data(biu_data_i)
    );

    logic [SRAM_STATE_WIDTH-1:0] wb_sram_state_r;
    logic [GATHER_COUNT_WIDTH-1:0] gather_idx_r;
    logic [GATHER_COUNT_WIDTH-1:0] gather_cnt_r;

    // Active low reset for the procyon_ff module
    logic n_rst;
    assign n_rst = ~i_wb_rst;

    // Determine if the access is unaligned
    // Unaligned accesses take an extra cycle to retrieve the last byte of data
    logic unaligned;
    logic [WB_DATA_SIZE+`SRAM_DATA_SIZE-1:0] sel_ua;
    logic [OPTN_WB_DATA_WIDTH+`SRAM_DATA_WIDTH-1:0] data_ua;

    assign unaligned = biu_addr[0];
    assign sel_ua = unaligned ? {1'b0, biu_sel, 1'b0} : {{(`SRAM_DATA_SIZE){1'b0}}, biu_sel};
    assign data_ua = unaligned ? {8'b0, biu_data_i, 8'b0} : {{(`SRAM_DATA_WIDTH){1'b0}}, biu_data_i};

    // Increment index to get next word from the WB bus on the next cycle for unaligned accesses
    logic [GATHER_COUNT_WIDTH:0] wb_gather_idx;
    assign wb_gather_idx = (wb_sram_state_r == SRAM_STATE_UNALIGNED & ~biu_we) | (wb_sram_state_r == SRAM_STATE_WRITE_ACK & unaligned) ? gather_idx_r + 1'b1 : {1'b0, gather_idx_r};

    logic [`SRAM_DATA_SIZE-1:0] sel;
    logic [`SRAM_ADDR_WIDTH-1:0] addr;
    logic [`SRAM_DATA_WIDTH-1:0] data_i;

    assign sel = sel_ua[wb_gather_idx*`SRAM_DATA_SIZE +: `SRAM_DATA_SIZE];
    assign addr = biu_addr[`SRAM_ADDR_WIDTH:1];
    assign data_i = data_ua[wb_gather_idx*`SRAM_DATA_WIDTH +: `SRAM_DATA_WIDTH];

    // WB SRAM FSM
    // GATHER_COUNT refers to how many operations it takes to read/write all the data from/to the wishbone bus to/from the SRAM
    // The SRAM can only handle 16 bit reads/writes in each cycle which means, depending on the wishbone data bus size, the read/write
    // will take place over multiple cycles. For example, if the WB data bus is 32 bits then a read operation will take two cycles
    // to gather the data from the SRAM and a third cycle to ACK. A write operation will take two cycles in total since the second
    // packet of 16 bits can be written to the SRAM in the same cycle the ACK is asserted with no issues.
    // The GATHER_COUNT is statically determined at elaboration time thus the state machine below will be different depending on the
    // GATHER_COUNT value. It is true that if the WB data bus is 16 bits (i.e the same as the SRAM data bus) then read/write operations
    // can take a single cycle (+ a second cycle for the ACK) and so the READ_GATHER/WRITE_GATHER states can be completely skipped.
    // Moreover, (as an optimization) in the case of GATHER_COUNT <= 2 (i.e. 16 bit or 32 bit WB data bus) the WRITE_GATHER state can
    // be completely skipped for writes since the last write packet can be committed to the SRAM on the same cycle the ACK is asserted.
    // Gather count and index register FSM
    // Tie these registers to zero if GATHER_COUNT == 1 (i.e. SRAM and WB data bus are the same widths, 16 bits)
    logic [SRAM_STATE_WIDTH-1:0] wb_sram_state_next;
    logic [GATHER_COUNT_WIDTH-1:0] gather_cnt_next;
    logic [GATHER_COUNT_WIDTH-1:0] gather_idx_next;
    logic [GATHER_COUNT_WIDTH-1:0] gather_cnt_next_idle_val;
    logic [GATHER_COUNT_WIDTH-1:0] gather_idx_next_idle_val;
    logic [GATHER_COUNT_WIDTH-1:0] gather_cnt_next_default_val;
    logic [GATHER_COUNT_WIDTH-1:0] gather_idx_next_default_val;
    logic [SRAM_STATE_WIDTH-1:0] wb_sram_state_next_idle_val_a;
    logic [SRAM_STATE_WIDTH-1:0] wb_sram_state_next_idle_val_b;
    logic [SRAM_STATE_WIDTH-1:0] wb_sram_state_next_read_ack_val;
    logic [SRAM_STATE_WIDTH-1:0] wb_sram_state_next_write_ack_val;

    generate
    if (GATHER_COUNT > 2)      assign wb_sram_state_next_idle_val_a = SRAM_STATE_WRITE_GATHER;
    else if (GATHER_COUNT > 1) assign wb_sram_state_next_idle_val_a = unaligned ? SRAM_STATE_UNALIGNED : SRAM_STATE_WRITE_ACK;
    else                       assign wb_sram_state_next_idle_val_a = SRAM_STATE_WRITE_ACK;
    endgenerate

    generate
    if (GATHER_COUNT > 1) begin
        assign gather_cnt_next_idle_val = biu_en ? GATHER_COUNT_WIDTH'(INITIAL_GATHER_COUNT-1) : GATHER_COUNT_WIDTH'(INITIAL_GATHER_COUNT);
        assign gather_idx_next_idle_val = biu_en ? GATHER_COUNT_WIDTH'(1) : '0;
        assign gather_cnt_next_default_val = gather_cnt_r - 1'b1;
        assign gather_idx_next_default_val = gather_idx_r + 1'b1;
        assign wb_sram_state_next_idle_val_b = SRAM_STATE_READ_GATHER;
        assign wb_sram_state_next_read_ack_val = SRAM_STATE_READ_GATHER;
        assign wb_sram_state_next_write_ack_val = SRAM_STATE_WRITE_GATHER;
    end else begin
        assign gather_cnt_next_idle_val = '0;
        assign gather_idx_next_idle_val = '0;
        assign gather_cnt_next_default_val = '0;
        assign gather_idx_next_default_val = '0;
        assign wb_sram_state_next_idle_val_b = unaligned ? SRAM_STATE_UNALIGNED : SRAM_STATE_READ_ACK;
        assign wb_sram_state_next_read_ack_val = unaligned ? SRAM_STATE_UNALIGNED : SRAM_STATE_READ_ACK;
        assign wb_sram_state_next_write_ack_val = unaligned ? SRAM_STATE_UNALIGNED : SRAM_STATE_WRITE_ACK;
    end
    endgenerate

    always_comb begin
        logic n_biu_eob;
        n_biu_eob = ~biu_eob;

        case (wb_sram_state_r)
            SRAM_STATE_IDLE: begin
                gather_cnt_next = gather_cnt_next_idle_val;
                gather_idx_next = gather_idx_next_idle_val;

                wb_sram_state_next = biu_we ? wb_sram_state_next_idle_val_a : (biu_en ? wb_sram_state_next_idle_val_b : SRAM_STATE_IDLE);
            end
            SRAM_STATE_READ_ACK: begin
                gather_cnt_next = gather_cnt_next_default_val;
                gather_idx_next = gather_idx_next_default_val;

                wb_sram_state_next = n_biu_eob ? wb_sram_state_next_read_ack_val : SRAM_STATE_IDLE;
            end
            SRAM_STATE_WRITE_ACK: begin
                gather_cnt_next = gather_cnt_next_default_val;
                gather_idx_next = gather_idx_next_default_val;

                wb_sram_state_next = n_biu_eob ? wb_sram_state_next_write_ack_val : SRAM_STATE_IDLE;
            end
            SRAM_STATE_READ_GATHER: begin
                gather_cnt_next = gather_cnt_next_default_val;
                gather_idx_next = gather_idx_next_default_val;

                wb_sram_state_next = (gather_cnt_r == 0) ? (unaligned ? SRAM_STATE_UNALIGNED : SRAM_STATE_READ_ACK) : SRAM_STATE_READ_GATHER;
            end
            SRAM_STATE_WRITE_GATHER: begin
                gather_cnt_next = gather_cnt_next_default_val;
                gather_idx_next = gather_idx_next_default_val;

                wb_sram_state_next = (gather_cnt_next == 0) ? (unaligned ? SRAM_STATE_UNALIGNED : SRAM_STATE_WRITE_ACK) : SRAM_STATE_WRITE_GATHER;
            end
            SRAM_STATE_UNALIGNED: begin
                gather_cnt_next = gather_cnt_r;
                gather_idx_next = gather_idx_r;

                wb_sram_state_next = biu_we ? SRAM_STATE_WRITE_ACK : SRAM_STATE_READ_ACK;
            end
            default: begin
                gather_cnt_next = gather_cnt_next_default_val;
                gather_idx_next = gather_idx_next_default_val;

                wb_sram_state_next = SRAM_STATE_IDLE;
            end
        endcase
    end

    procyon_srff #(SRAM_STATE_WIDTH) wb_sram_state_r_srff (.clk(i_wb_clk), .n_rst(n_rst), .i_en(1'b1), .i_set(wb_sram_state_next), .i_reset(SRAM_STATE_IDLE), .o_q(wb_sram_state_r));
    procyon_srff #(GATHER_COUNT_WIDTH) gather_cnt_r_srff (.clk(i_wb_clk), .n_rst(n_rst), .i_en(1'b1), .i_set(gather_cnt_next), .i_reset('0), .o_q(gather_cnt_r));
    procyon_srff #(GATHER_COUNT_WIDTH) gather_idx_r_srff (.clk(i_wb_clk), .n_rst(n_rst), .i_en(1'b1), .i_set(gather_idx_next), .i_reset('0), .o_q(gather_idx_r));

    logic done;
    assign done = (wb_sram_state_next == SRAM_STATE_READ_ACK) | (wb_sram_state_next == SRAM_STATE_WRITE_ACK);
    procyon_srff #(1) biu_done_r_srff (.clk(i_wb_clk), .n_rst(n_rst), .i_en(1'b1), .i_set(done), .i_reset(1'b0), .o_q(biu_done_r));

    // Internal storage for SRAM outputs while gathering data over multiple cycles
/* verilator lint_off UNUSED */
    logic [OPTN_WB_DATA_WIDTH-1:0] data_o;
/* verilator lint_on  UNUSED */
    genvar data_o_idx;
    generate
    for (data_o_idx = 0 ; data_o_idx < GATHER_COUNT; data_o_idx++) begin : GEN_DATA_O_FF
        logic data_o_en;
        assign data_o_en = gather_idx_r == data_o_idx;
        procyon_ff #(`SRAM_DATA_WIDTH) data_o_ff (.clk(i_wb_clk), .i_en(data_o_en), .i_d(io_sram_dq), .o_q(data_o[data_o_idx*`SRAM_DATA_WIDTH +: `SRAM_DATA_WIDTH]));
    end
    endgenerate

    // Output SRAM data to BIU. Slightly different behaviour depending on GATHER_COUNT
    // The unaligned case is the same but the for GATHER_COUNT > 1, the last gather from the SRAM is 16-bit MSB of the output
    logic [OPTN_WB_DATA_WIDTH-1:0] data_a;
    logic [OPTN_WB_DATA_WIDTH-1:0] data_b;
    logic [OPTN_WB_DATA_WIDTH-1:0] data_mux;

    assign data_a = {io_sram_dq[7:0], data_o[OPTN_WB_DATA_WIDTH-1:8]};
    generate
    if (GATHER_COUNT > 1) assign data_b = {io_sram_dq, data_o[OPTN_WB_DATA_WIDTH-`SRAM_DATA_WIDTH-1:0]};
    else                  assign data_b = io_sram_dq;
    endgenerate

    assign data_mux = (wb_sram_state_r == SRAM_STATE_UNALIGNED) ? data_a : data_b;
    procyon_ff #(OPTN_WB_DATA_WIDTH) biu_data_r_ff (.clk(i_wb_clk), .i_en(1'b1), .i_d(data_mux), .o_q(biu_data_o_r));

    // Assign SRAM outputs. Keep chip & output enable asserted
    assign o_sram_ce_n = 1'b0;
    assign o_sram_oe_n = 1'b0;
    assign o_sram_we_n = ~biu_we;
    assign o_sram_lb_n = ~sel[0];
    assign o_sram_ub_n = ~sel[1];
    assign o_sram_addr = addr + ((wb_sram_state_r == SRAM_STATE_READ_ACK) ? `SRAM_ADDR_WIDTH'(GATHER_COUNT) : `SRAM_ADDR_WIDTH'(wb_gather_idx));
    assign io_sram_dq = biu_we ? data_i : 'z;

endmodule
