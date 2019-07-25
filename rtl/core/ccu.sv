// Core Communications Unit
// This module is responsible for arbitrating between the MHQ, fetch and
// victim requests within the CPU and controlling the BIU

`include "procyon_constants.svh"

module ccu #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_MHQ_DEPTH     = 4,
    parameter OPTN_DC_LINE_SIZE  = 1024,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_WB_DATA_WIDTH = 16,

    localparam MHQ_IDX_WIDTH     = $clog2(OPTN_MHQ_DEPTH),
    localparam DC_LINE_WIDTH     = OPTN_DC_LINE_SIZE * 8,
    localparam WB_WORD_SIZE      = OPTN_WB_DATA_WIDTH / 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    // MHQ address/tag lookup interface
    input  logic                            i_mhq_lookup_valid,
    input  logic                            i_mhq_lookup_dc_hit,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_mhq_lookup_addr,
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0] i_mhq_lookup_lsu_func,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_mhq_lookup_data,
    input  logic                            i_mhq_lookup_we,
    output logic                            o_mhq_lookup_retry,
    output logic [MHQ_IDX_WIDTH-1:0]        o_mhq_lookup_tag,

    // Fill cacheline
    output logic                            o_mhq_fill_en,
    output logic [MHQ_IDX_WIDTH-1:0]        o_mhq_fill_tag,
    output logic                            o_mhq_fill_dirty,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_mhq_fill_addr,
    output logic [DC_LINE_WIDTH-1:0]        o_mhq_fill_data,

    // Wishbone bus interface
    input  logic                            i_wb_clk,
    input  logic                            i_wb_rst,
    input  logic                            i_wb_ack,
    input  logic                            i_wb_stall,
    input  logic [OPTN_WB_DATA_WIDTH-1:0]   i_wb_data,
    output logic                            o_wb_cyc,
    output logic                            o_wb_stb,
    output logic                            o_wb_we,
    output logic [WB_WORD_SIZE-1:0]         o_wb_sel,
    output logic [OPTN_WB_ADDR_WIDTH-1:0]   o_wb_addr,
    output logic [OPTN_WB_DATA_WIDTH-1:0]   o_wb_data
);

    localparam CCU_STATE_WIDTH = 2;
    localparam CCU_STATE_IDLE  = 2'b00;
    localparam CCU_STATE_REQ   = 2'b01;
    localparam CCU_STATE_WAIT  = 2'b10;
    localparam CCU_STATE_DONE  = 2'b11;

    logic [CCU_STATE_WIDTH-1:0] next_state;
    logic [CCU_STATE_WIDTH-1:0] state_q;
    logic                       ccu_en;
    logic                       ccu_done;
    logic                       biu_done;
    logic                       biu_busy;
    logic [DC_LINE_WIDTH-1:0]   biu_data_r;
    logic [DC_LINE_WIDTH-1:0]   biu_data_w;
    logic [OPTN_ADDR_WIDTH-1:0] biu_addr;
    logic                       biu_we;
    logic                       biu_en;

    // Output to BIU
    assign biu_data_w = {{(DC_LINE_WIDTH){1'b0}}};
    assign biu_we     = 1'b0;
    assign biu_en     = state_q == CCU_STATE_REQ | state_q == CCU_STATE_WAIT;

    // Output done signal
    assign ccu_done   = state_q == CCU_STATE_DONE;

    // Latch next state
    always_ff @(posedge clk) begin
        if (~n_rst) state_q <= CCU_STATE_IDLE;
        else        state_q <= next_state;
    end

    // Update state
    always_comb begin
        case (state_q)
            CCU_STATE_IDLE: next_state = (ccu_en & ~biu_busy) ? CCU_STATE_REQ : CCU_STATE_IDLE;
            CCU_STATE_REQ:  next_state = CCU_STATE_WAIT;
            CCU_STATE_WAIT: next_state = biu_done ? CCU_STATE_DONE : CCU_STATE_WAIT;
            CCU_STATE_DONE: next_state = CCU_STATE_IDLE;
        endcase
    end

    mhq #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE)
    ) mhq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_mhq_lookup_valid(i_mhq_lookup_valid),
        .i_mhq_lookup_dc_hit(i_mhq_lookup_dc_hit),
        .i_mhq_lookup_addr(i_mhq_lookup_addr),
        .i_mhq_lookup_lsu_func(i_mhq_lookup_lsu_func),
        .i_mhq_lookup_data(i_mhq_lookup_data),
        .i_mhq_lookup_we(i_mhq_lookup_we),
        .o_mhq_lookup_retry(o_mhq_lookup_retry),
        .o_mhq_lookup_tag(o_mhq_lookup_tag),
        .o_mhq_fill_en(o_mhq_fill_en),
        .o_mhq_fill_tag(o_mhq_fill_tag),
        .o_mhq_fill_dirty(o_mhq_fill_dirty),
        .o_mhq_fill_addr(o_mhq_fill_addr),
        .o_mhq_fill_data(o_mhq_fill_data),
        .i_ccu_done(ccu_done),
        .i_ccu_data(biu_data_r),
        .o_ccu_en(ccu_en),
        .o_ccu_addr(biu_addr)
    );

    wb_biu #(
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE)
    ) wb_biu_inst (
        .i_wb_clk(i_wb_clk),
        .i_wb_rst(i_wb_rst),
        .i_wb_ack(i_wb_ack),
        .i_wb_stall(i_wb_stall),
        .i_wb_data(i_wb_data),
        .o_wb_cyc(o_wb_cyc),
        .o_wb_stb(o_wb_stb),
        .o_wb_we(o_wb_we),
        .o_wb_sel(o_wb_sel),
        .o_wb_addr(o_wb_addr),
        .o_wb_data(o_wb_data),
        .i_biu_en(biu_en),
        .i_biu_we(biu_we),
        .i_biu_addr(biu_addr),
        .i_biu_data(biu_data_w),
        .o_biu_data(biu_data_r),
        .o_biu_busy(biu_busy),
        .o_biu_done(biu_done)
    );

endmodule
