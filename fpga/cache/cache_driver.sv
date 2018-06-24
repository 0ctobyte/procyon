
`include "../../common/test_common.svh"

module cache_driver #(
    parameter  DATA_WIDTH         = `DATA_WIDTH,
    parameter  ADDR_WIDTH         = `WB_ADDR_WIDTH,
    parameter  CACHE_SIZE         = `CACHE_SIZE,
    parameter  CACHE_LINE_SIZE    = `CACHE_LINE_SIZE
) (
    input  logic                           clk,
    input  logic                           n_rst,

    input  logic                           i_cache_driver_re,
    input  logic                           i_cache_driver_we,
    input  logic [ADDR_WIDTH-1:0]          i_cache_driver_addr,
    input  logic [DATA_WIDTH-1:0]          i_cache_driver_data,
    output logic [DATA_WIDTH-1:0]          o_cache_driver_data,
    output logic                           o_cache_driver_hit,
    output logic                           o_cache_driver_busy,

    input  logic                           i_cache_driver_biu_done,
    input  logic                           i_cache_driver_biu_busy,
    input  logic [CACHE_LINE_SIZE*8-1:0]   i_cache_driver_biu_data,
    output logic                           o_cache_driver_biu_en,
    output logic                           o_cache_driver_biu_we,
    output logic [ADDR_WIDTH-1:0]          o_cache_driver_biu_addr,
    output logic [CACHE_LINE_SIZE*8-1:0]   o_cache_driver_biu_data
);

    localparam CACHE_WORD_SIZE    = DATA_WIDTH/8;
    localparam CACHE_INDEX_COUNT  = CACHE_SIZE/CACHE_LINE_SIZE;
    localparam CACHE_OFFSET_WIDTH = $clog2(CACHE_LINE_SIZE);
    localparam CACHE_INDEX_WIDTH  = $clog2(CACHE_INDEX_COUNT);
    localparam CACHE_TAG_WIDTH    = ADDR_WIDTH-CACHE_INDEX_WIDTH-CACHE_OFFSET_WIDTH;
    localparam CACHE_LINE_WIDTH   = CACHE_LINE_SIZE*8;

    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        MISS    = 2'b01,
        VICTIM  = 2'b10,
        INVALID = 2'b11
    } state_t;

    state_t                        state;
    state_t                        state_q;

    logic [CACHE_OFFSET_WIDTH-1:0] cache_offset;
    logic [CACHE_INDEX_WIDTH-1:0]  cache_index;
    logic [CACHE_TAG_WIDTH-1:0]    cache_tag_i;
    logic [CACHE_TAG_WIDTH-1:0]    cache_tag_o;
    logic [CACHE_LINE_WIDTH-1:0]   cache_vdata;
    logic                          cache_hit;
    logic                          cache_dirty_i;
    logic                          cache_dirty_o;
    logic                          cache_valid;
    logic                          cache_we;
    logic                          cache_fe;

    logic                          victimized;
    logic [CACHE_LINE_WIDTH-1:0]   vdata_q;
    logic [ADDR_WIDTH-1:0]         vaddr_q;

    assign cache_offset            = i_cache_driver_addr[CACHE_OFFSET_WIDTH-1:0];
    assign cache_index             = i_cache_driver_addr[CACHE_INDEX_WIDTH+CACHE_OFFSET_WIDTH-1:CACHE_OFFSET_WIDTH];
    assign cache_tag_i             = i_cache_driver_addr[ADDR_WIDTH-1:ADDR_WIDTH-CACHE_TAG_WIDTH];

    assign victimized              = (i_cache_driver_biu_done && (state_q != VICTIM) && cache_dirty_o);
    assign cache_dirty_i           = 1'b0;
    assign cache_valid             = 1'b1;
    assign cache_we                = (state_q == VICTIM) ? 1'b0 : i_cache_driver_we;
    assign cache_fe                = (state_q == VICTIM) ? 1'b0 : i_cache_driver_biu_done;
    assign o_cache_driver_hit      = cache_hit;
    assign o_cache_driver_busy     = state_q != IDLE;
    assign o_cache_driver_biu_we   = i_cache_driver_we || (state_q == VICTIM);
    assign o_cache_driver_biu_en   = state_q != IDLE;
    assign o_cache_driver_biu_addr = (state_q == VICTIM) ? vaddr_q : {cache_tag_i, cache_index, {(CACHE_OFFSET_WIDTH){1'b0}}};
    assign o_cache_driver_biu_data = vdata_q;

    always_ff @(posedge clk) begin
        if (~n_rst) begin
            vdata_q  <= 'b0;
            vaddr_q  <= 'b0;
        end else if (i_cache_driver_biu_done && (state_q != VICTIM)) begin
            vdata_q  <= cache_vdata;
            vaddr_q  <= {cache_tag_o, cache_index, {(CACHE_OFFSET_WIDTH){1'b0}}};
        end
    end

    always_ff @(posedge clk) begin
        if (~n_rst) begin
            state_q <= IDLE;
        end else begin
            state_q <= state;
        end
    end

    always_comb begin
        case (state_q)
            IDLE:   state = ((i_cache_driver_re || i_cache_driver_we) && ~cache_hit) ? MISS : IDLE;
            MISS:   state = i_cache_driver_biu_done ? (victimized ? VICTIM : IDLE) : MISS;
            VICTIM: state = i_cache_driver_biu_done ? IDLE : VICTIM;
        endcase
    end

    cache #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .CACHE_SIZE(CACHE_SIZE),
        .CACHE_LINE_SIZE(CACHE_LINE_SIZE)
    ) cache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_cache_re(i_cache_driver_re),
        .i_cache_we(cache_we),
        .i_cache_fe(cache_fe),
        .i_cache_valid(cache_valid),
        .i_cache_dirty(cache_dirty_i),
        .i_cache_offset(cache_offset),
        .i_cache_index(cache_index),
        .i_cache_tag(cache_tag_i),
        .i_cache_fdata(i_cache_driver_biu_data),
        .i_cache_wdata(i_cache_driver_data),
        .o_cache_dirty(cache_dirty_o),
        .o_cache_hit(cache_hit),
        .o_cache_tag(cache_tag_o),
        .o_cache_vdata(cache_vdata),
        .o_cache_rdata(o_cache_driver_data)
    );

endmodule
