// Instruction fetch unit

module simple_fetch #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  n_rst,

    input  logic                  i_redirect,
    input  logic [ADDR_WIDTH-1:0] i_redirect_addr,

    // Interface to instruction memory (TODO: Too simple, needs cache interface)
    input  logic [DATA_WIDTH-1:0] i_insn,
    input  logic                  i_data_valid,
    output logic [ADDR_WIDTH-1:0] o_pc,
    output logic                  o_en,

    // Instruction FIFO interface
    fifo_wr_if.sys                insn_fifo_wr
);

    logic [ADDR_WIDTH-1:0] pc;

    assign o_en = ~insn_fifo_wr.full && ~i_redirect;
    assign o_pc = pc;

    assign insn_fifo_wr.wr_en   = i_data_valid;
    assign insn_fifo_wr.data_in = {pc, i_insn};

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
