module dp_ram_tb;

    logic clk;
    logic n_rst;

    dp_ram_if #(
        .DATA_WIDTH(8),
        .RAM_DEPTH(8)
    ) if_dp_ram ();

    dp_ram #(
        .DATA_WIDTH(8),
        .RAM_DEPTH(8),
        .BASE_ADDR(0)
    ) dut (
        .clk(clk),
        .n_rst(n_rst),
        .if_dp_ram(if_dp_ram)
    );

endmodule
