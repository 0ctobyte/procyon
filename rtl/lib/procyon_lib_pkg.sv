/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

package procyon_lib_pkg;
    // Size to width
    `define PCYN_S2W(size) ((size) * 8)

    // Width to size
    `define PCYN_W2S(width) ((width) / 8)

    // Count to Index width
    `define PCYN_C2I(count) (((count) == 1) ? 1 : $clog2(count))

    // Cache defines
    `define PCYN_CACHE_OFFSET_WIDTH ($clog2(OPTN_CACHE_LINE_SIZE))
    `define PCYN_CACHE_INDEX_COUNT (OPTN_CACHE_SIZE / OPTN_CACHE_LINE_SIZE)
    `define PCYN_CACHE_INDEX_WIDTH (`PCYN_C2I(`PCYN_CACHE_INDEX_COUNT))
    `define PCYN_CACHE_TAG_WIDTH (OPTN_ADDR_WIDTH - (`PCYN_CACHE_INDEX_WIDTH == 1 ? 0 : `PCYN_CACHE_INDEX_WIDTH) - `PCYN_CACHE_OFFSET_WIDTH)

    // BIU operations
    localparam PCYN_BIU_FUNC_WIDTH = 2;
    typedef enum logic [PCYN_BIU_FUNC_WIDTH-1:0] {
        PCYN_BIU_FUNC_READ  = PCYN_BIU_FUNC_WIDTH'('b00),
        PCYN_BIU_FUNC_WRITE = PCYN_BIU_FUNC_WIDTH'('b01),
        PCYN_BIU_FUNC_RMW   = PCYN_BIU_FUNC_WIDTH'('b10)
    } pcyn_biu_func_t;

    // BIU burst lengths
    localparam PCYN_BIU_LEN_WIDTH = 3;
    localparam PCYN_BIU_LEN_MAX_SIZE = 128;
    typedef enum logic [PCYN_BIU_LEN_WIDTH-1:0] {
        PCYN_BIU_LEN_1B   = PCYN_BIU_LEN_WIDTH'('b000),
        PCYN_BIU_LEN_2B   = PCYN_BIU_LEN_WIDTH'('b001),
        PCYN_BIU_LEN_4B   = PCYN_BIU_LEN_WIDTH'('b010),
        PCYN_BIU_LEN_8B   = PCYN_BIU_LEN_WIDTH'('b011),
        PCYN_BIU_LEN_16B  = PCYN_BIU_LEN_WIDTH'('b100),
        PCYN_BIU_LEN_32B  = PCYN_BIU_LEN_WIDTH'('b101),
        PCYN_BIU_LEN_64B  = PCYN_BIU_LEN_WIDTH'('b110),
        PCYN_BIU_LEN_128B = PCYN_BIU_LEN_WIDTH'('b111)
    } pcyn_biu_len_t;
    localparam pcyn_biu_len_t PCYN_BIU_LEN_MAX = PCYN_BIU_LEN_128B;

    // Wishbone bus Cycle Type Identifiers
    localparam WB_CTI_WIDTH = 3;
    typedef enum logic [WB_CTI_WIDTH-1:0] {
        WB_CTI_CLASSIC      = WB_CTI_WIDTH'('b000),
        WB_CTI_CONSTANT     = WB_CTI_WIDTH'('b001),
        WB_CTI_INCREMENTING = WB_CTI_WIDTH'('b010),
        WB_CTI_END_OF_BURST = WB_CTI_WIDTH'('b111)
    } wb_cti_t;

    // Wishbone bus Burst Type Extensions
    localparam WB_BTE_WIDTH = 2;
    typedef enum logic [WB_BTE_WIDTH-1:0] {
        WB_BTE_LINEAR = WB_BTE_WIDTH'('b00),
        WB_BTE_4BEAT  = WB_BTE_WIDTH'('b01),
        WB_BTE_8BEAT  = WB_BTE_WIDTH'('b10),
        WB_BTE_16BEAT = WB_BTE_WIDTH'('b11)
    } wb_bte_t;
endpackage: procyon_lib_pkg