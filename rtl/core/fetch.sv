// Instruction fetch unit

`include "common.svh"
import procyon_types::*;

module fetch (
    input  logic                     clk,
    input  logic                     n_rst,

    input  logic                     i_redirect,
    input  procyon_addr_t            i_redirect_addr,

    // Interface to instruction memory (TODO: Too simple, needs cache interface)
    input  procyon_data_t            i_insn,
    input  logic                     i_data_valid,
    output procyon_addr_t            o_pc,
    output logic                     o_en,

    // Interface to dispatcher
    input  logic                     i_dispatch_stall,
    output procyon_addr_t            o_dispatch_pc,
    output procyon_data_t            o_dispatch_insn,
    output logic                     o_dispatch_valid
);

    procyon_addr_t                   pc;
    procyon_addr_t                   insn_pc;
    procyon_addr_t                   next_pc;
    procyon_addr_t                   pc_plus_4;
    logic [1:0]                      pc_sel;
    logic                            insn_fifo_ack;
    logic                            insn_fifo_full;
    procyon_addr_data_t              insn_fifo_data_o;
    procyon_addr_data_t              insn_fifo_data_i;
    logic                            redirect_d;
    logic                            data_valid;

    assign data_valid                = i_data_valid | redirect_d;
    assign insn_fifo_ack             = ~i_dispatch_stall;
    assign insn_fifo_data_i          = {insn_pc, i_insn};

    assign pc_sel                    = {i_redirect, data_valid & ~insn_fifo_full};
    assign pc_plus_4                 = pc + 4;

    // PC mux
    assign next_pc                   = mux4_addr(pc, pc_plus_4, i_redirect_addr, i_redirect_addr, pc_sel);

    assign o_en                      = ~i_redirect;
    assign o_pc                      = insn_fifo_full | ~data_valid ? insn_pc : pc;

    assign o_dispatch_pc             = insn_fifo_data_o[`ADDR_WIDTH+`DATA_WIDTH-1:`DATA_WIDTH];
    assign o_dispatch_insn           = insn_fifo_data_o[`DATA_WIDTH-1:0];

    always_ff @(posedge clk) begin
        if (~n_rst) begin
            pc         <= {(`ADDR_WIDTH){1'b0}};
            redirect_d <= 1'b0;
        end else begin
            pc         <= next_pc;
            redirect_d <= i_redirect;
        end
    end

    always_ff @(posedge clk) begin
        if (~insn_fifo_full) insn_pc <= pc;
    end

    sync_fifo #(
        .DATA_WIDTH(`ADDR_WIDTH+`DATA_WIDTH),
        .FIFO_DEPTH(8)
    ) insn_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_redirect),
        .i_fifo_ack(insn_fifo_ack),
        .o_fifo_data(insn_fifo_data_o),
        .o_fifo_valid(o_dispatch_valid),
        .i_fifo_we(i_data_valid),
        .i_fifo_data(insn_fifo_data_i),
        .o_fifo_full(insn_fifo_full)
    );

endmodule
