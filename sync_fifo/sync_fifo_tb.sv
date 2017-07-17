module sync_fifo_tb;

    logic clk;
    logic n_rst;

    logic i_flush;

    fifo_wr_if #(
        .DATA_WIDTH(8)
    ) if_fifo_wr ();

    fifo_rd_if #(
        .DATA_WIDTH(8)
    ) if_fifo_rd ();

    sync_fifo #(
        .DATA_WIDTH(8),
        .FIFO_DEPTH(8)
    ) dut (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .if_fifo_wr(if_fifo_wr),
        .if_fifo_rd(if_fifo_rd)
    );

endmodule
