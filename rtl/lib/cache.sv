// Basic direct-mapped cache

module cache #(
    parameter OPTN_DATA_WIDTH      = 32,
    parameter OPTN_ADDR_WIDTH      = 32,
    parameter OPTN_CACHE_SIZE      = 1024,
    parameter OPTN_CACHE_LINE_SIZE = 32,

    parameter CACHE_INDEX_COUNT    = OPTN_CACHE_SIZE / OPTN_CACHE_LINE_SIZE,
    parameter CACHE_INDEX_WIDTH    = $clog2(CACHE_INDEX_COUNT),
    parameter CACHE_TAG_WIDTH      = OPTN_ADDR_WIDTH - CACHE_INDEX_WIDTH - $clog2(OPTN_CACHE_LINE_SIZE),
    parameter CACHE_LINE_WIDTH     = OPTN_CACHE_LINE_SIZE * 8
) (
    input  logic                                clk,
    input  logic                                n_rst,

    // Interface to read/write data to cache
    // i_cache_rd_en = read enable
    // i_cache_wr_en = write enable
    // i_cache_wr_valid and i_cache_wr_dirty are only written into the state when i_cache_wr_en
    // asserted. i_cache_wr_index chooses the index into the cache and i_cache_wr_tag is written
    // into the tag ram
    input  logic                         i_cache_wr_en,
    input  logic [CACHE_INDEX_WIDTH-1:0] i_cache_wr_index,
    input  logic                         i_cache_wr_valid,
    input  logic                         i_cache_wr_dirty,
    input  logic [CACHE_TAG_WIDTH-1:0]   i_cache_wr_tag,
    input  logic [CACHE_LINE_WIDTH-1:0]  i_cache_wr_data,

    // o_cache_rd_data is the data requested on a read access
    // o_cache_rd_dirty, o_cache_rd_valid, and o_cache_rd_tag are output on a read access
    // o_cache_rd_data is the whole cacheline (in case of victimizing cachelines)
    // and o_cache_rd_tag is output as well (for victimized cachelines)
    input  logic                         i_cache_rd_en,
    input  logic [CACHE_INDEX_WIDTH-1:0] i_cache_rd_index,
    output logic                         o_cache_rd_valid,
    output logic                         o_cache_rd_dirty,
    output logic [CACHE_TAG_WIDTH-1:0]   o_cache_rd_tag,
    output logic [CACHE_LINE_WIDTH-1:0]  o_cache_rd_data
);


    logic cache_state_valid_q [0:CACHE_INDEX_COUNT-1];
    logic cache_state_dirty_q [0:CACHE_INDEX_COUNT-1];

    // Assign outputs
    always_ff @(posedge clk) begin
        if (~n_rst) o_cache_rd_valid <= 1'b0;
        else        o_cache_rd_valid <= (i_cache_rd_index == i_cache_wr_index) & i_cache_wr_en ? i_cache_wr_valid : cache_state_valid_q[i_cache_rd_index];
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_cache_rd_dirty <= 1'b0;
        else        o_cache_rd_dirty <= (i_cache_rd_index == i_cache_wr_index) & i_cache_wr_en ? i_cache_wr_dirty : cache_state_dirty_q[i_cache_rd_index];
    end

    // Update the valid bit on a fill
    always_ff @(posedge clk) begin
        if (~n_rst) begin
            for (int i = 0; i < CACHE_INDEX_COUNT; i++) begin
                cache_state_valid_q[i] <= 1'b0;
            end
        end else if (i_cache_wr_en) begin
            cache_state_valid_q[i_cache_wr_index] <= i_cache_wr_valid;
        end
    end

    // Update the dirty bit on a write and on a fill
    always_ff @(posedge clk) begin
        if (~n_rst) begin
            for (int i = 0; i < CACHE_INDEX_COUNT; i++) begin
                cache_state_dirty_q[i] <= 1'b0;
            end
        end else if (i_cache_wr_en) begin
            cache_state_dirty_q[i_cache_wr_index] <= i_cache_wr_dirty;
        end
    end

    // Instantiate the DATA and TAG RAMs
    sdpb_ram #(
        .OPTN_DATA_WIDTH(CACHE_LINE_WIDTH),
        .OPTN_RAM_DEPTH(CACHE_INDEX_COUNT)
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
        .OPTN_DATA_WIDTH(CACHE_TAG_WIDTH),
        .OPTN_RAM_DEPTH(CACHE_INDEX_COUNT)
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
