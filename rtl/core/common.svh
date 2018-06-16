// Common defines

`define CDB_DEPTH        2
`define REGMAP_DEPTH     32
`define ROB_DEPTH        32
`define RS_IEU_DEPTH     16
`define RS_LSU_DEPTH     16
`define LQ_DEPTH         8
`define SQ_DEPTH         8
`define MHQ_DEPTH        4

`define DATA_WIDTH       32
`define ADDR_WIDTH       32
`define TAG_WIDTH        $clog2(`ROB_DEPTH)
`define REG_ADDR_WIDTH   $clog2(`REGMAP_DEPTH)
`define LQ_TAG_WIDTH     $clog2(`LQ_DEPTH)
`define MHQ_TAG_WIDTH    $clog2(`MHQ_DEPTH)

`define WORD_SIZE        `DATA_WIDTH/8

`define DC_CACHE_SIZE    1024
`define DC_LINE_SIZE     32
`define DC_WAY_COUNT     1
`define DC_INDEX_COUNT   (`DC_CACHE_SIZE/`DC_LINE_SIZE/`DC_WAY_COUNT)

`define DC_OFFSET_WIDTH  $clog2(`DC_LINE_SIZE)
`define DC_INDEX_WIDTH   $clog2(`DC_INDEX_COUNT)
`define DC_WAY_WIDTH     $clog2(`DC_WAY_COUNT)
`define DC_TAG_WIDTH     (`ADDR_WIDTH-`DC_INDEX_WIDTH-`DC_OFFSET_WIDTH)
`define DC_LINE_WIDTH    (`DC_LINE_SIZE*8)

`define WB_DATA_WIDTH    16
`define WB_ADDR_WIDTH    (`ADDR_WIDTH)
