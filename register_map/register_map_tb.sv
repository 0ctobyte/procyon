`define DATA_WIDTH 32
`define REGMAP_DEPTH 32
`define ROB_DEPTH 64
`define TAG_WIDTH $clog2(`ROB_DEPTH)
`define REG_ADDR_WIDTH $clog2(`REGMAP_DEPTH)

module register_map_tb;

    logic clk;
    logic n_rst;

    logic i_flush;

    always begin
        #10 clk = ~clk;
    end

    initial begin
        clk = 'b1;
        n_rst = 'b0;
        i_flush = 'b0;

        dest_wr.data = 'b0;
        dest_wr.rdest = 'b0;
        dest_wr.wr_en = 'b0;
        tag_wr.tag = 'b0;
        tag_wr.rdest = 'b0;
        tag_wr.wr_en = 'b0;
        regmap_lookup.rsrc[0] = 'b0;
        regmap_lookup.rsrc[1] = 'b0;

        #10 n_rst = 'b1;
    end

    regmap_dest_wr_if #(
        .DATA_WIDTH(`DATA_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) dest_wr ();

    regmap_tag_wr_if #(
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) tag_wr ();

    regmap_lookup_if #(
        .DATA_WIDTH(`DATA_WIDTH),
        .TAG_WIDTH(`TAG_WIDTH),
        .REG_ADDR_WIDTH(`REG_ADDR_WIDTH)
    ) regmap_lookup ();

    register_map #(
        .DATA_WIDTH(`DATA_WIDTH),
        .REGMAP_DEPTH(`REGMAP_DEPTH),
        .TAG_WIDTH(`TAG_WIDTH)
    ) regmap (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .dest_wr(dest_wr),
        .tag_wr(tag_wr),
        .regmap_lookup(regmap_lookup)
    );

endmodule
