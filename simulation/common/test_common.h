#define SRAM_ADDR_WIDTH    (20)
#define SRAM_DATA_WIDTH    (16)
#define SRAM_SIZE          (1 << (SRAM_ADDR_WIDTH+1))

#define WB_ADDR_WIDTH      (32)
#define WB_DATA_WIDTH      (16)

#ifdef DATA_WIDTH_32
    #define DATA_WIDTH     (32)
#else
    #define DATA_WIDTH     (WB_DATA_WIDTH)
#endif
#define ADDR_WIDTH         (WB_ADDR_WIDTH)

#define CACHE_SIZE         (256)
#define CACHE_LINE_SIZE    (32)

#define CACHE_WORD_SIZE    (DATA_WIDTH/8)
#define CACHE_INDEX_COUNT  (CACHE_SIZE/CACHE_LINE_SIZE)
#define CACHE_OFFSET_WIDTH ((uint32_t)ceil(log2(CACHE_LINE_SIZE)))
#define CACHE_INDEX_WIDTH  ((uint32_t)ceil(log2(CACHE_INDEX_COUNT)))
#define CACHE_TAG_WIDTH    (ADDR_WIDTH-CACHE_INDEX_WIDTH-CACHE_OFFSET_WIDTH)
#define CACHE_LINE_WIDTH   (CACHE_LINE_SIZE*8)
