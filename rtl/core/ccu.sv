// Core Communications Unit
// This module is responsible for arbitrating between the MHQ, fetch and
// victim requests within the CPU and controlling the BIU

`include "common.svh"
import procyon_types::*;

module ccu (
    input  logic                   clk,
    input  logic                   n_rst,

    // Indicate if MHQ is full
    output logic                   o_mhq_full,

    // Fill cacheline
    output logic                   o_mhq_fill,
    output procyon_mhq_tag_t       o_mhq_fill_tag,
    output logic                   o_mhq_fill_dirty,
    output procyon_addr_t          o_mhq_fill_addr,
    output procyon_cacheline_t     o_mhq_fill_data,

    // MHQ enqueue interface
    input  logic                   i_mhq_enq_en,
    input  logic                   i_mhq_enq_we,
    input  procyon_addr_t          i_mhq_enq_addr,
    input  procyon_data_t          i_mhq_enq_data,
    input  procyon_byte_select_t   i_mhq_enq_byte_select,
    output procyon_mhq_tag_t       o_mhq_enq_tag,

    // Wishbone bus interface
    input  logic                   i_wb_clk,
    input  logic                   i_wb_rst,
    input  logic                   i_wb_ack,
    input  logic                   i_wb_stall,
    input  wb_data_t               i_wb_data,
    output logic                   o_wb_cyc,
    output logic                   o_wb_stb,
    output logic                   o_wb_we,
    output wb_byte_select_t        o_wb_sel,
    output wb_addr_t               o_wb_addr,
    output wb_data_t               o_wb_data
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        REQ  = 2'b01,
        WAIT = 2'b10,
        DONE = 2'b11
    } state_t;

    state_t               next_state;
    state_t               state_q;
    logic                 ccu_en;
    logic                 ccu_done;
    logic                 biu_done;
    logic                 biu_busy;
    procyon_cacheline_t   biu_data_r;
    procyon_cacheline_t   biu_data_w;
    procyon_addr_t        biu_addr;
    logic                 biu_we;
    logic                 biu_en;

    // Output to BIU
    assign biu_data_w     = {{(`DC_LINE_WIDTH){1'b0}}};
    assign biu_we         = 1'b0;
    assign biu_en         = state_q == REQ | state_q == WAIT;

    // Output done signal
    assign ccu_done       = state_q == DONE;

    // Latch next state
    always_ff @(posedge clk) begin
        if (~n_rst) state_q <= IDLE;
        else        state_q <= next_state;
    end

    // Update state
    always_comb begin
        case (state_q)
            IDLE: next_state = (ccu_en & ~biu_busy) ? REQ : IDLE;
            REQ:  next_state = WAIT;
            WAIT: next_state = biu_done ? DONE : WAIT;
            DONE: next_state = IDLE;
        endcase
    end

    miss_handling_queue mhq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .o_mhq_full(o_mhq_full),
        .o_mhq_fill(o_mhq_fill),
        .o_mhq_fill_tag(o_mhq_fill_tag),
        .o_mhq_fill_dirty(o_mhq_fill_dirty),
        .o_mhq_fill_addr(o_mhq_fill_addr),
        .o_mhq_fill_data(o_mhq_fill_data),
        .i_mhq_enq_en(i_mhq_enq_en),
        .i_mhq_enq_we(i_mhq_enq_we),
        .i_mhq_enq_addr(i_mhq_enq_addr),
        .i_mhq_enq_data(i_mhq_enq_data),
        .i_mhq_enq_byte_select(i_mhq_enq_byte_select),
        .o_mhq_enq_tag(o_mhq_enq_tag),
        .i_ccu_done(ccu_done),
        .i_ccu_data(biu_data_r),
        .o_ccu_addr(biu_addr),
        .o_ccu_en(ccu_en)
    );

    wb_biu wb_biu_inst (
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
