module rom_tb;

    logic clk;
    logic n_rst;

    logic [$clog2(8)-1:0] i_rd_addr;
    logic [7:0]           o_data_out;

    rom #(
        .DATA_WIDTH(8),
        .ROM_DEPTH(8),
        .BASE_ADDR(0),
        .ROM_FILE("rom_init.txt")
    ) dut (
        .clk(clk),
        .n_rst(n_rst),
        .i_rd_addr(i_rd_addr),
        .o_data_out(o_data_out)
    );

endmodule
