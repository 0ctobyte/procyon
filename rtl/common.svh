// Common defines

`define REGMAP_DEPTH     32
`define ROB_DEPTH        32
`define RS_DEPTH         16
`define LQ_DEPTH         8
`define SQ_DEPTH         8

`define DATA_WIDTH       32
`define ADDR_WIDTH       32
`define TAG_WIDTH        $clog2(`ROB_DEPTH)
`define REG_ADDR_WIDTH   $clog2(`REGMAP_DEPTH)

`define DC_CACHE_SIZE   2048
`define DC_LINE_SIZE    32
`define DC_WAY_COUNT    2
`define DC_SET_COUNT    (`DC_CACHE_SIZE/`DC_LINE_SIZE/`DC_WAY_COUNT)

`define DC_LINE_WIDTH   $clog2(`DC_LINE_SIZE)
`define DC_SET_WIDTH    $clog2(`DC_SET_COUNT)
`define DC_WAY_WIDTH    $clog2(`DC_WAY_COUNT)
`define DC_TAG_WIDTH    (`ADDR_WIDTH-`DC_INDEX_WIDTH-`DC_LINE_WIDTH)
