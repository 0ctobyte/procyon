// Instruction fetch unit

`include "common.svh"

module fetch #(
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ADDR_WIDTH = `ADDR_WIDTH
) (
    input  logic                             clk,
    input  logic                             n_rst,

    input  logic                             i_redirect,
    input  logic [ADDR_WIDTH-1:0]            i_redirect_addr,

    // Interface to instruction memory (TODO: Too simple, needs cache interface)
    input  logic [DATA_WIDTH-1:0]            i_insn,
    input  logic                             i_data_valid,
    output logic [ADDR_WIDTH-1:0]            o_pc,
    output logic                             o_en,

    // Instruction FIFO interface
    input  logic                             i_insn_fifo_full,
    output logic [ADDR_WIDTH+DATA_WIDTH-1:0] o_insn_fifo_data,
    output logic                             o_insn_fifo_wr_en
);

    logic [ADDR_WIDTH-1:0] pc;

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
