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
    // i_cache_re = read enable
    // i_cache_we = write enable
    // i_cache_fe = fill enable
    // i_cache_valid and i_cache_dirty will be written to the valid bit when fill enable is
    // asserted. i_cache_offset is the byte offset into the cache line.
    // i_cache_index chooses the index into the cache and i_cache_tag is used
    // for tag comparisons. i_cache_fdata is the fill data when writing an
    // entire cache line at once and i_cache_wdata is for cache line updates
    input  logic                                i_cache_re,
    input  logic                                i_cache_we,
    input  logic                                i_cache_fe,
    input  logic                                i_cache_valid,
    input  logic                                i_cache_dirty,
    input  logic [`LIB_CACHE_OFFSET_WIDTH-1:0]  i_cache_offset,
    input  logic [`LIB_CACHE_INDEX_WIDTH-1:0]   i_cache_index,
    input  logic [`LIB_CACHE_TAG_WIDTH-1:0]     i_cache_tag,
    input  logic [`LIB_CACHE_LINE_WIDTH-1:0]    i_cache_fdata,
    input  logic [DATA_WIDTH-1:0]               i_cache_wdata,

    // o_cache_dirty and o_cache_hit is output on every cache
    // access so that the consumer knows whether to write back the data.
    // o_cache_tag and o_cache_vdata are also outputted in case a cache line
    // is victimized. The old tag is needed to determine the victim address.
    // o_cache_rdata is the data requested on a read access
    output logic                                o_cache_dirty,
    output logic                                o_cache_hit,
    output logic [`LIB_CACHE_TAG_WIDTH-1:0]     o_cache_tag,
    output logic [`LIB_CACHE_LINE_WIDTH-1:0]    o_cache_vdata,
    output logic [DATA_WIDTH-1:0]               o_cache_rdata
);

    typedef struct packed {
        logic      valid;
        logic      dirty;
    } cache_state_t;

    cache_state_t                       cache_state [0:`LIB_CACHE_INDEX_COUNT-1];
    logic                               cache_line_valid;
    logic                               cache_line_dirty;
    logic                               cache_line_hit;
    logic                               cache_we;
    logic [CACHE_LINE_SIZE-1:0]         cache_offset_select [0:`LIB_CACHE_WORD_SIZE-1];

    logic                               data_ram_re;
    logic                               data_ram_we;
    logic [`LIB_CACHE_LINE_WIDTH-1:0]   data_ram_rd_data;
    logic [`LIB_CACHE_LINE_WIDTH-1:0]   data_ram_wr_data;

    logic                               tag_ram_re;
    logic                               tag_ram_we;
    logic [`LIB_CACHE_TAG_WIDTH-1:0]    tag_ram_rd_data;
    logic [`LIB_CACHE_TAG_WIDTH-1:0]    tag_ram_wr_data;

    assign cache_line_valid    = cache_state[i_cache_index].valid;
    assign cache_line_dirty    = cache_state[i_cache_index].dirty && cache_line_valid;
    assign cache_line_hit      = (tag_ram_rd_data == i_cache_tag) && cache_line_valid;
    assign cache_we            = i_cache_we && cache_line_hit;

    // Always read out the old cacheline on a read, write or fill
    // On a cache update (i.e. write), make sure the tag hits in the tag ram
    assign data_ram_re         = i_cache_re || i_cache_we || i_cache_fe;
    assign data_ram_we         = cache_we || i_cache_fe;
    assign tag_ram_re          = data_ram_re;
    assign tag_ram_we          = i_cache_fe;
    assign tag_ram_wr_data     = i_cache_tag;

    // Assign outputs
    assign o_cache_dirty       = cache_line_dirty;
    assign o_cache_hit         = cache_line_hit;
    assign o_cache_tag         = tag_ram_rd_data;
    assign o_cache_vdata       = data_ram_rd_data;

    genvar g;
    generate
        // Need to determine which bytes in the cache line are to be written
        // to or read from
        for (g = 0; g < `LIB_CACHE_WORD_SIZE; g++) begin : GENERATE_OFFSET_SELECT
            assign cache_offset_select[g] = 1 << (i_cache_offset + g);
        end
    endgenerate

    // Each byte in the output o_cache_rdata word is muxed with each byte of
    // the cacheline using cache_offset_select as the select signal.
    always_comb begin
        for (int i = 0; i < `LIB_CACHE_WORD_SIZE; i++) begin
            o_cache_rdata[i*8 +: 8] = 8'b0;
            for (int j = 0; j < CACHE_LINE_SIZE; j++) begin
                if (cache_offset_select[i][j]) begin
                    o_cache_rdata[i*8 +: 8] = data_ram_rd_data[j*8 +: 8];
                end
            end
        end
    end

    // If fill enable is asserted than every byte to be written will come from
    // i_cache_fdata. If write enable is asserted then select the bytes to be
    // written using cache_offset_select. Otherwise just write back the
    // same bytes that were read out from the cache line.
    always_comb begin
        for (int i = 0; i < CACHE_LINE_SIZE; i++) begin
            data_ram_wr_data[i*8 +: 8] = data_ram_rd_data[i*8 +: 8];
            if (cache_we) begin
                for (int j = 0; j < `LIB_CACHE_WORD_SIZE; j++) begin
                    if (cache_offset_select[j][i]) begin
                        data_ram_wr_data[i*8 +: 8] = i_cache_wdata[j*8 +: 8];
                    end
                end
            end else if (i_cache_fe) begin
                data_ram_wr_data[i*8 +: 8] = i_cache_fdata[i*8 +: 8];
            end
        end
    end

    // Update the valid bit on a fill
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            for (int i = 0; i < `LIB_CACHE_INDEX_COUNT; i++) begin
                cache_state[i].valid <= 1'b0;
            end
        end else if (i_cache_fe) begin
            cache_state[i_cache_index].valid <= i_cache_valid;
        end
    end

    // Update the dirty bit on a write and on a fill
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            for (int i = 0; i < `LIB_CACHE_INDEX_COUNT; i++) begin
                cache_state[i].dirty <= 1'b0;
            end
        end else if (i_cache_fe) begin
            cache_state[i_cache_index].dirty <= i_cache_dirty;
        end else if (cache_we) begin
            cache_state[i_cache_index].dirty <= 1'b1;
        end
    end

    // Instantiate the DATA and TAG RAMs
    dp_ram #(
        .DATA_WIDTH(`LIB_CACHE_LINE_WIDTH),
        .RAM_DEPTH(`LIB_CACHE_INDEX_COUNT)
    ) data_ram (
        .clk(clk),
        .n_rst(n_rst),
        .i_ram_rd_en(data_ram_re),
        .i_ram_rd_addr(i_cache_index),
        .o_ram_rd_data(data_ram_rd_data),
        .i_ram_wr_en(data_ram_we),
        .i_ram_wr_addr(i_cache_index),
        .i_ram_wr_data(data_ram_wr_data)
    );

    dp_ram #(
        .DATA_WIDTH(`LIB_CACHE_TAG_WIDTH),
        .RAM_DEPTH(`LIB_CACHE_INDEX_COUNT)
    ) tag_ram (
        .clk(clk),
        .n_rst(n_rst),
        .i_ram_rd_en(tag_ram_re),
        .i_ram_rd_addr(i_cache_index),
        .o_ram_rd_data(tag_ram_rd_data),
        .i_ram_wr_en(tag_ram_we),
        .i_ram_wr_addr(i_cache_index),
        .i_ram_wr_data(tag_ram_wr_data)
    );

endmodule
