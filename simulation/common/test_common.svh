`define SRAM_ADDR_WIDTH       (20)
`define SRAM_DATA_WIDTH       (16)

`ifndef WB_DATA_WIDTH
    `define WB_DATA_WIDTH     (16)
`endif
`ifndef WB_ADDR_WIDTH
    `define WB_ADDR_WIDTH     (32)
`endif
`ifndef WB_WORD_SIZE
    `define WB_WORD_SIZE      (`WB_DATA_WIDTH/8)
`endif

`define WB_SRAM_BASE_ADDR     (0)
`define WB_SRAM_FIFO_DEPTH    (8)

`ifndef DATA_WIDTH
    `define DATA_WIDTH        (`WB_DATA_WIDTH)
`endif

`ifndef ADDR_WIDTH
    `define ADDR_WIDTH        (`WB_ADDR_WIDTH)
`endif

`define CACHE_SIZE            (256)
`define CACHE_LINE_SIZE       (32)

`define CACHE_WORD_SIZE       (`DATA_WIDTH/8)
`define CACHE_INDEX_COUNT     (`CACHE_SIZE/`CACHE_LINE_SIZE)
`define CACHE_OFFSET_WIDTH    ($clog2(`CACHE_LINE_SIZE))
`define CACHE_INDEX_WIDTH     ($clog2(`CACHE_INDEX_COUNT))
`define CACHE_TAG_WIDTH       (`ADDR_WIDTH-`CACHE_INDEX_WIDTH-`CACHE_OFFSET_WIDTH)
`define CACHE_LINE_WIDTH      (`CACHE_LINE_SIZE*8)

`ifndef DC_CACHE_SIZE
    `define DC_CACHE_SIZE     (256)
`endif
`ifndef DC_LINE_SIZE
    `define DC_LINE_SIZE      (`CACHE_LINE_SIZE)
`endif
`ifndef DC_WAY_COUNT
    `define DC_WAY_COUNT      (1)
`endif

`ifndef DC_INDEX_COUNT
    `define DC_INDEX_COUNT    (`DC_CACHE_SIZE/`DC_LINE_SIZE/`DC_WAY_COUNT)
`endif
`ifndef DC_OFFSET_WIDTH
    `define DC_OFFSET_WIDTH   $clog2(`DC_LINE_SIZE)
`endif
`ifndef DC_INDEX_WIDTH
    `define DC_INDEX_WIDTH    $clog2(`DC_INDEX_COUNT)
`endif
`ifndef DC_WAY_WIDTH
    `define DC_WAY_WIDTH      $clog2(`DC_WAY_COUNT)
`endif
`ifndef DC_TAG_WIDTH
    `define DC_TAG_WIDTH      (`ADDR_WIDTH-`DC_INDEX_WIDTH-`DC_OFFSET_WIDTH)
`endif
`ifndef DC_LINE_WIDTH
    `define DC_LINE_WIDTH     (`DC_LINE_SIZE*8)
`endif
