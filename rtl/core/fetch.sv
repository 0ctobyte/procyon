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

    // Instruction FIFO interface
    input  logic                     i_insn_fifo_full,
    output procyon_addr_data_t       o_insn_fifo_data,
    output logic                     o_insn_fifo_wr_en
);

    procyon_addr_t             pc;
    procyon_addr_t             next_pc;
    procyon_addr_t             pc_plus_4;
    logic [1:0]                pc_sel;

    assign o_en                = ~i_insn_fifo_full & ~i_redirect;
    assign o_pc                = pc;

    assign o_insn_fifo_wr_en   = i_data_valid;
    assign o_insn_fifo_data    = {pc, i_insn};

    assign pc_sel              = {i_redirect, i_data_valid};
    assign pc_plus_4           = pc + 4;

    // PC mux
    assign next_pc             = mux4_addr(pc, pc_plus_4, i_redirect_addr, i_redirect_addr, pc_sel);

    always_ff @(posedge clk) begin
        if (~n_rst) pc <= {(`ADDR_WIDTH){1'b0}};
        else        pc <= next_pc;
    end

endmodule
