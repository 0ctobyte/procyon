// Basic direct-mapped cache

`define LIB_CACHE_WORD_SIZE       (DATA_WIDTH/8)
`define LIB_CACHE_INDEX_COUNT     (CACHE_SIZE/CACHE_LINE_SIZE)
`define LIB_CACHE_OFFSET_WIDTH    ($clog2(CACHE_LINE_SIZE))
`define LIB_CACHE_INDEX_WIDTH     ($clog2(`LIB_CACHE_INDEX_COUNT))
`define LIB_CACHE_TAG_WIDTH       (ADDR_WIDTH-`LIB_CACHE_INDEX_WIDTH-`LIB_CACHE_OFFSET_WIDTH)
`define LIB_CACHE_LINE_WIDTH      (CACHE_LINE_SIZE*8)

module cache #(
    parameter   DATA_WIDTH      = 32,
    parameter   ADDR_WIDTH      = 32,
    parameter   CACHE_SIZE      = 1024,
    parameter   CACHE_LINE_SIZE = 32
) (
    input  logic                                clk,
    input  logic                                n_rst,

    // Interface to read/write data to cache
    // i_cache_rd_en = read enable
    // i_cache_wr_en = write enable
    // i_cache_wr_valid and i_cache_wr_dirty are only written into the state when i_cache_wr_en
    // asserted. i_cache_wr_index chooses the index into the cache and i_cache_wr_tag is written
    // into the tag ram
    input  logic                                i_cache_wr_en,
    input  logic [`LIB_CACHE_INDEX_WIDTH-1:0]   i_cache_wr_index,
    input  logic                                i_cache_wr_valid,
    input  logic                                i_cache_wr_dirty,
    input  logic [`LIB_CACHE_TAG_WIDTH-1:0]     i_cache_wr_tag,
    input  logic [`LIB_CACHE_LINE_WIDTH-1:0]    i_cache_wr_data,

    // o_cache_rd_data is the data requested on a read access
    // o_cache_rd_dirty, o_cache_rd_valid, and o_cache_rd_tag are output on a read access
    // o_cache_rd_data is the whole cacheline (in case of victimizing cachelines)
    // and o_cache_rd_tag is output as well (for victimized cachelines)
    input  logic                                i_cache_rd_en,
    input  logic [`LIB_CACHE_INDEX_WIDTH-1:0]   i_cache_rd_index,
    output logic                                o_cache_rd_valid,
    output logic                                o_cache_rd_dirty,
    output logic [`LIB_CACHE_TAG_WIDTH-1:0]     o_cache_rd_tag,
    output logic [`LIB_CACHE_LINE_WIDTH-1:0]    o_cache_rd_data
);

    typedef struct packed {
        logic      valid;
        logic      dirty;
    } cache_state_t;

    cache_state_t  cache_state [0:`LIB_CACHE_INDEX_COUNT-1];

    // Assign outputs
    always_ff @(posedge clk) begin
        if (~n_rst) o_cache_rd_valid <= 1'b0;
        else        o_cache_rd_valid <= (i_cache_rd_index == i_cache_wr_index) & i_cache_wr_en ? i_cache_wr_valid : cache_state[i_cache_rd_index].valid;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_cache_rd_dirty <= 1'b0;
        else        o_cache_rd_dirty <= (i_cache_rd_index == i_cache_wr_index) & i_cache_wr_en ? i_cache_wr_dirty : cache_state[i_cache_rd_index].dirty;
    end

    // Update the valid bit on a fill
    always_ff @(posedge clk) begin
        if (~n_rst) begin
            for (int i = 0; i < `LIB_CACHE_INDEX_COUNT; i++) begin
                cache_state[i].valid <= 1'b0;
            end
        end else if (i_cache_wr_en) begin
            cache_state[i_cache_wr_index].valid <= i_cache_wr_valid;
        end
    end

    // Update the dirty bit on a write and on a fill
    always_ff @(posedge clk) begin
        if (~n_rst) begin
            for (int i = 0; i < `LIB_CACHE_INDEX_COUNT; i++) begin
                cache_state[i].dirty <= 1'b0;
            end
        end else if (i_cache_wr_en) begin
            cache_state[i_cache_wr_index].dirty <= i_cache_wr_dirty;
        end
    end

    // Instantiate the DATA and TAG RAMs
    sdpb_ram #(
        .DATA_WIDTH(`LIB_CACHE_LINE_WIDTH),
        .RAM_DEPTH(`LIB_CACHE_INDEX_COUNT)
    ) data_ram (
        .clk(clk),
        .i_ram_re(i_cache_rd_en),
        .i_ram_addr_r(i_cache_rd_index),
        .o_ram_data(o_cache_rd_data),
        .i_ram_we(i_cache_wr_en),
        .i_ram_addr_w(i_cache_wr_index),
        .i_ram_data(i_cache_wr_data)
    );

    sdpb_ram #(
        .DATA_WIDTH(`LIB_CACHE_TAG_WIDTH),
        .RAM_DEPTH(`LIB_CACHE_INDEX_COUNT)
    ) tag_ram (
        .clk(clk),
        .i_ram_re(i_cache_rd_en),
        .i_ram_addr_r(i_cache_rd_index),
        .o_ram_data(o_cache_rd_tag),
        .i_ram_we(i_cache_wr_en),
        .i_ram_addr_w(i_cache_wr_index),
        .i_ram_data(i_cache_wr_tag)
    );

endmodule
