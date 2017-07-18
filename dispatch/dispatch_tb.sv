`timescale 1ns/1ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 32
`define TAG_WIDTH  6
`define REG_ADDR_WIDTH 5

module dispatch_tb;

    logic clk;
    logic n_rst;

    logic i_flush;

    // Clock generation
    initial clk = 'b0;
    always #10 clk = ~clk;

    initial begin
        n_rst = 'b0;
        i_flush = 'b0;
        insn_fifo_wr.wr_en = 'b0;
        insn_fifo_wr.data_in = 'b0;

        #20 n_rst = 'b1;
    end

    fifo_wr_if #(
        .DATA_WIDTH(`DATA_WIDTH)
    ) insn_fifo_wr ();

    fifo_rd_if #(
        .DATA_WIDTH(`DATA_WIDTH)
    ) insn_fifo_rd ();

    rs_dispatch_if #(
        .ADDR_WIDTH(`ADDR_WIDTH),
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) rs_dispatch ();

    rob_dispatch_if #(
        .ADDR_WIDTH(`ADDR_WIDTH),
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) rob_dispatch ();

    sync_fifo #(
        .DATA_WIDTH(`ADDR_WIDTH+`DATA_WIDTH),
        .FIFO_DEPTH(8)
    ) insn_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .if_fifo_wr(insn_fifo_wr),
        .if_fifo_rd(insn_fifo_rd)
    );

    dispatch #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .n_rst(n_rst),
        .insn_fifo_rd(insn_fifo_rd),
        .rs_dispatch(rs_dispatch),
        .rob_dispatch(rob_dispatch)
    );

endmodule
