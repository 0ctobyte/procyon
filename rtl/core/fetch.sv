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

    procyon_addr_t pc;

    assign o_en                = ~i_insn_fifo_full && ~i_redirect;
    assign o_pc                = pc;

    assign o_insn_fifo_wr_en   = i_data_valid;
    assign o_insn_fifo_data    = {pc, i_insn};

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            pc <= 'b0;
        end else if (i_redirect) begin
            pc <= i_redirect_addr;
        end else if (i_data_valid) begin
            pc <= pc + 4;
        end
    end

endmodule
