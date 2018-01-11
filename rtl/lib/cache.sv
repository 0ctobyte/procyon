// Basic direct-mapped cache

module cache #(
    parameter   DATA_WIDTH      = 32,
    parameter   ADDR_WIDTH      = 32,
    parameter   CACHE_SIZE      = 1024,
    parameter   CACHE_LINE_SIZE = 32,
    localparam  WORD_SIZE       = DATA_WIDTH/8,
    localparam  CACHE_SET_COUNT = CACHE_SIZE/CACHE_LINE_SIZE,
    localparam  LINE_WIDTH      = $clog2(CACHE_LINE_SIZE),
    localparam  SET_WIDTH       = $clog2(CACHE_SET_COUNT),
    localparam  TAG_WIDTH       = ADDR_WIDTH-SET_WIDTH-LINE_WIDTH
) (
    input  logic                     clk,
    input  logic                     n_rst,

    // For reads, i_cache_re is asserted and the word specified by i_cache_word
    // is read out from the set specified by i_cache_set. For writes,
    // i_cache_we is asserted and the word specified by i_cache_word is
    // written to in the set specified by i_cache_set. The valid bit is also
    // written to using the value specified by i_cache_valid.
    input  logic                     i_cache_re,
    input  logic                     i_cache_we,
    input  logic                     i_cache_valid,
    input  logic [LINE_WIDTH-1:0]    i_cache_word,
    input  logic [SET_WIDTH-1:0]     i_cache_set,
    input  logic [TAG_WIDTH-1:0]     i_cache_tag,
    input  logic [DATA_WIDTH-1:0]    i_cache_data,

    // All reads will output the valid and dirty state of the cacheline as
    // well as the tag (for evictions) and hit status
    output logic                     o_cache_hit,
    output logic                     o_cache_valid,
    output logic                     o_cache_dirty,
    output logic [TAG_WIDTH-1:0]     o_cache_tag,
    output logic [DATA_WIDTH-1:0]    o_cache_data
);
   
    // Each cache state holds a collection of state information
    // valid:          Indicates whether the line is valid
    // dirty:          Indicates whether the line is dirty
    // tag:            Tag information for hit calculation
    typedef struct {
        logic                    valid;
        logic                    dirty;
        logic [TAG_WIDTH-1:0]    tag;
    } cache_state_t;

    // The tag RAM is structured as follows
    // -----------------------------------
    // | v | d |          tag            |
    // ----------------------------------
    // | v | d |          tag            |
    // ----------------------------------
    // | v | d |          tag            |
    // ----------------------------------
    // ....
    // Where v = valid and d = dirty
    //
    // The Data RAM is structured as follows
    // ------------------------------------------------------------
    // |   byte0   |    byte1   |   byte2   |   byte3   |   ...   |
    // ------------------------------------------------------------
    // |   byte0   |    byte1   |   byte2   |   byte3   |   ...   |
    // ------------------------------------------------------------
    // |   byte0   |    byte1   |   byte2   |   byte3   |   ...   |
    // ------------------------------------------------------------
    // ...
    // Each set is composed of an array of bytes
    typedef struct {
        cache_state_t  tags  [0:CACHE_SET_COUNT-1];
        logic [7:0]    data  [0:CACHE_SET_COUNT-1][0:CACHE_LINE_SIZE-1];
    } cache_t;

    cache_t cache;

    logic                 valid;
    logic                 dirty;
    logic [TAG_WIDTH-1:0] tag;

    // Read tag information on a cache read access
    assign valid         = i_cache_re ? cache.tags[i_cache_set].valid : 1'b0;
    assign dirty         = i_cache_re ? cache.tags[i_cache_set].dirty : 1'b0;
    assign tag           = i_cache_re ? cache.tags[i_cache_set].tag   : 'b0;

    // Read the cacheline if i_cache_re is asserted
    // No functionality to read across two cachelines
    genvar i;
    generate
    for (i = 0; i < WORD_SIZE; i++) begin : ASSIGN_DATA_READ_OUTPUT
        assign o_cache_data[(i+1)*8-1:i*8] = i_cache_re ? cache.data[i_cache_set][i_cache_word+i] : 8'b0;
    end
    endgenerate

    // Output cache state information on cache read access
    assign o_cache_valid = i_cache_re ? valid : 1'b0;
    assign o_cache_dirty = i_cache_re ? dirty : 1'b0;
    assign o_cache_tag   = i_cache_re ? tag   : 'b0;
    assign o_cache_hit   = i_cache_re ? (tag == i_cache_tag) : 1'b0;

    // Make sure all valid bits are cleared on reset
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            for (int i = 0; i < CACHE_SET_COUNT; i++) begin
                cache.tags[i].valid <= 1'b0;
            end
        end else if (i_cache_we) begin
            cache.tags[i_cache_set].valid <= i_cache_valid;
        end
    end

    // Make sure all dirty bits are cleared on reset
    // Only update dirty bits if i_cache_we is asserted and i_cache_valid is set
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            for (int i = 0; i< CACHE_SET_COUNT; i++) begin
                cache.tags[i].dirty <= 1'b0;
            end
        end else if (i_cache_we && valid) begin
            cache.tags[i_cache_set].dirty <= 1'b1;
        end
    end

    // Update data and tags
    always_ff @(posedge clk) begin
        if (i_cache_we) begin
            cache.tags[i_cache_set].tags <= i_cache_tag;
            for (int i = 0; i < WORD_SIZE; i++) begin
                o_cache.data[i_cache_set][i_cache_word+i] <= i_cache_data[(i+1)*8-1:i*8];
            end
        end
    end

endmodule
