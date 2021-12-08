/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDS-License-Identifier: MIT
 */

`ifndef _PROCYON_CORE_PKG_SVH_
`define _PROCYON_CORE_PKG_SVH_

package procyon_core_pkg;
    import procyon_lib_pkg::*;

    // Instruction Cache defines
    `define PCYN_IC_OFFSET_WIDTH ($clog2(OPTN_IC_LINE_SIZE))
    `define PCYN_IC_INDEX_COUNT (OPTN_IC_CACHE_SIZE / OPTN_IC_LINE_SIZE)
    `define PCYN_IC_INDEX_WIDTH (`PCYN_C2I(`PCYN_IC_INDEX_COUNT))
    `define PCYN_IC_TAG_WIDTH (OPTN_ADDR_WIDTH - (`PCYN_IC_INDEX_WIDTH == 1 ? 0 : `PCYN_IC_INDEX_WIDTH) - `PCYN_IC_OFFSET_WIDTH)

    // Data Cache defines
    `define PCYN_DC_OFFSET_WIDTH ($clog2(OPTN_DC_LINE_SIZE))
    `define PCYN_DC_INDEX_COUNT (OPTN_DC_CACHE_SIZE / OPTN_DC_LINE_SIZE)
    `define PCYN_DC_INDEX_WIDTH (`PCYN_C2I(`PCYN_DC_INDEX_COUNT))
    `define PCYN_DC_TAG_WIDTH (OPTN_ADDR_WIDTH - (`PCYN_DC_INDEX_WIDTH == 1 ? 0 : `PCYN_DC_INDEX_WIDTH) - `PCYN_DC_OFFSET_WIDTH)

    // RS functional unit types
    localparam PCYN_RS_FU_TYPE_WIDTH = 2;
    typedef enum logic [PCYN_RS_FU_TYPE_WIDTH-1:0] {
        PCYN_RS_FU_TYPE_IEU = PCYN_RS_FU_TYPE_WIDTH'('b01),
        PCYN_RS_FU_TYPE_LSU = PCYN_RS_FU_TYPE_WIDTH'('b10)
    } pcyn_rs_fu_type_t;

    localparam PCYN_RS_FU_TYPE_IDX_WIDTH = $clog2(PCYN_RS_FU_TYPE_WIDTH);
    typedef enum logic [PCYN_RS_FU_TYPE_IDX_WIDTH-1:0] {
        PCYN_RS_FU_TYPE_IDX_IEU = PCYN_RS_FU_TYPE_IDX_WIDTH'('b0),
        PCYN_RS_FU_TYPE_IDX_LSU = PCYN_RS_FU_TYPE_IDX_WIDTH'('b1)
    } pcyn_rs_fu_type_idx_t;

    // General operation types according to RV spec
    localparam PCYN_RV_OPCODE_WIDTH = 7;
    typedef enum logic [PCYN_RV_OPCODE_WIDTH-1:0] {
        PCYN_RV_OPCODE_OPIMM  = PCYN_RV_OPCODE_WIDTH'('b0010011),
        PCYN_RV_OPCODE_LUI    = PCYN_RV_OPCODE_WIDTH'('b0110111),
        PCYN_RV_OPCODE_AUIPC  = PCYN_RV_OPCODE_WIDTH'('b0010111),
        PCYN_RV_OPCODE_OP     = PCYN_RV_OPCODE_WIDTH'('b0110011),
        PCYN_RV_OPCODE_JAL    = PCYN_RV_OPCODE_WIDTH'('b1101111),
        PCYN_RV_OPCODE_JALR   = PCYN_RV_OPCODE_WIDTH'('b1100111),
        PCYN_RV_OPCODE_BRANCH = PCYN_RV_OPCODE_WIDTH'('b1100011),
        PCYN_RV_OPCODE_LOAD   = PCYN_RV_OPCODE_WIDTH'('b0000011),
        PCYN_RV_OPCODE_STORE  = PCYN_RV_OPCODE_WIDTH'('b0100011)
    } pcyn_rv_opcode_t;

    // Procyon op types
    localparam PCYN_OP_IS_WIDTH = 4;
    typedef enum logic [PCYN_OP_IS_WIDTH-1:0] {
        PCYN_OP_IS_OP = PCYN_OP_IS_WIDTH'('b0000),
        PCYN_OP_IS_LD = PCYN_OP_IS_WIDTH'('b0001),
        PCYN_OP_IS_ST = PCYN_OP_IS_WIDTH'('b0010),
        PCYN_OP_IS_BR = PCYN_OP_IS_WIDTH'('b0100),
        PCYN_OP_IS_JL = PCYN_OP_IS_WIDTH'('b1000)
    } pcyn_op_is_t;

    localparam PCYN_OP_IS_IDX_WIDTH = $clog2(PCYN_OP_IS_WIDTH);
    typedef enum logic [PCYN_OP_IS_IDX_WIDTH-1:0] {
        PCYN_OP_IS_LD_IDX = PCYN_OP_IS_IDX_WIDTH'('b00),
        PCYN_OP_IS_ST_IDX = PCYN_OP_IS_IDX_WIDTH'('b01),
        PCYN_OP_IS_BR_IDX = PCYN_OP_IS_IDX_WIDTH'('b10),
        PCYN_OP_IS_JL_IDX = PCYN_OP_IS_IDX_WIDTH'('b11)
    } pcyn_op_is_idx_t;

    // Procyon operations
    localparam PCYN_OP_WIDTH = 5;
    typedef enum logic [PCYN_OP_WIDTH-1:0] {
        PCYN_OP_ADD       = PCYN_OP_WIDTH'('b00000),
        PCYN_OP_SUB       = PCYN_OP_WIDTH'('b00001),
        PCYN_OP_AND       = PCYN_OP_WIDTH'('b00010),
        PCYN_OP_OR        = PCYN_OP_WIDTH'('b00011),
        PCYN_OP_XOR       = PCYN_OP_WIDTH'('b00100),
        PCYN_OP_SLL       = PCYN_OP_WIDTH'('b00101),
        PCYN_OP_SRL       = PCYN_OP_WIDTH'('b00110),
        PCYN_OP_SRA       = PCYN_OP_WIDTH'('b00111),
        PCYN_OP_EQ        = PCYN_OP_WIDTH'('b01000),
        PCYN_OP_NE        = PCYN_OP_WIDTH'('b01001),
        PCYN_OP_LT        = PCYN_OP_WIDTH'('b01010),
        PCYN_OP_LTU       = PCYN_OP_WIDTH'('b01011),
        PCYN_OP_GE        = PCYN_OP_WIDTH'('b01100),
        PCYN_OP_GEU       = PCYN_OP_WIDTH'('b01101),
        PCYN_OP_LB        = PCYN_OP_WIDTH'('b01110),
        PCYN_OP_LH        = PCYN_OP_WIDTH'('b01111),
        PCYN_OP_LW        = PCYN_OP_WIDTH'('b10000),
        PCYN_OP_LBU       = PCYN_OP_WIDTH'('b10001),
        PCYN_OP_LHU       = PCYN_OP_WIDTH'('b10010),
        PCYN_OP_SB        = PCYN_OP_WIDTH'('b10011),
        PCYN_OP_SH        = PCYN_OP_WIDTH'('b10100),
        PCYN_OP_SW        = PCYN_OP_WIDTH'('b10101),
        PCYN_OP_FILL      = PCYN_OP_WIDTH'('b10110),
        PCYN_OP_UNDEFINED = PCYN_OP_WIDTH'('b11111)
    } pcyn_op_t;

    localparam PCYN_OP_SHAMT_WIDTH = 5;
    typedef logic [PCYN_OP_SHAMT_WIDTH-1:0] pcyn_op_shamt_t;

    // CCU burst lengths
    localparam PCYN_CCU_LEN_WIDTH = PCYN_BIU_LEN_WIDTH;
    localparam PCYN_CCU_LEN_MAX_SIZE = PCYN_BIU_LEN_MAX_SIZE;
    typedef enum logic [PCYN_CCU_LEN_WIDTH-1:0] {
        PCYN_CCU_LEN_1B   = PCYN_BIU_LEN_1B,
        PCYN_CCU_LEN_2B   = PCYN_BIU_LEN_2B,
        PCYN_CCU_LEN_4B   = PCYN_BIU_LEN_4B,
        PCYN_CCU_LEN_8B   = PCYN_BIU_LEN_8B,
        PCYN_CCU_LEN_16B  = PCYN_BIU_LEN_16B,
        PCYN_CCU_LEN_32B  = PCYN_BIU_LEN_32B,
        PCYN_CCU_LEN_64B  = PCYN_BIU_LEN_64B,
        PCYN_CCU_LEN_128B = PCYN_BIU_LEN_128B
    } pcyn_ccu_len_t;
    localparam pcyn_ccu_len_t PCYN_CCU_LEN_MAX = PCYN_CCU_LEN_128B;
endpackage: procyon_core_pkg

`endif // _PROCYON_CORE_PKG_SVH_
