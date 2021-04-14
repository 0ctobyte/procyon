/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDS-License-Identifier: MIT
 */

// Procyon constants

// RS functional unit types
`define PCYN_RS_FU_TYPE_WIDTH     2
`define PCYN_RS_FU_TYPE_IDX_WIDTH ($clog2(`PCYN_RS_FU_TYPE_WIDTH))
`define PCYN_RS_FU_TYPE_IDX_IEU   `PCYN_RS_FU_TYPE_IDX_WIDTH'(0)
`define PCYN_RS_FU_TYPE_IDX_LSU   `PCYN_RS_FU_TYPE_IDX_WIDTH'(1)
`define PCYN_RS_FU_TYPE_IEU       (`PCYN_RS_FU_TYPE_WIDTH'b01)
`define PCYN_RS_FU_TYPE_LSU       (`PCYN_RS_FU_TYPE_WIDTH'b10)

// General operation types according to RV spec
`define PCYN_RV_OPCODE_WIDTH  7
`define PCYN_RV_OPCODE_OPIMM  (`PCYN_RV_OPCODE_WIDTH'b0010011)
`define PCYN_RV_OPCODE_LUI    (`PCYN_RV_OPCODE_WIDTH'b0110111)
`define PCYN_RV_OPCODE_AUIPC  (`PCYN_RV_OPCODE_WIDTH'b0010111)
`define PCYN_RV_OPCODE_OP     (`PCYN_RV_OPCODE_WIDTH'b0110011)
`define PCYN_RV_OPCODE_JAL    (`PCYN_RV_OPCODE_WIDTH'b1101111)
`define PCYN_RV_OPCODE_JALR   (`PCYN_RV_OPCODE_WIDTH'b1100111)
`define PCYN_RV_OPCODE_BRANCH (`PCYN_RV_OPCODE_WIDTH'b1100011)
`define PCYN_RV_OPCODE_LOAD   (`PCYN_RV_OPCODE_WIDTH'b0000011)
`define PCYN_RV_OPCODE_STORE  (`PCYN_RV_OPCODE_WIDTH'b0100011)

// Procyon op types
`define PCYN_OP_IS_WIDTH     4
`define PCYN_OP_IS_OP        (`PCYN_OP_IS_WIDTH'b0000)
`define PCYN_OP_IS_LD        (`PCYN_OP_IS_WIDTH'b0001)
`define PCYN_OP_IS_ST        (`PCYN_OP_IS_WIDTH'b0010)
`define PCYN_OP_IS_BR        (`PCYN_OP_IS_WIDTH'b0100)
`define PCYN_OP_IS_JL        (`PCYN_OP_IS_WIDTH'b1000)
`define PCYN_OP_IS_IDX_WIDTH 2
`define PCYN_OP_IS_LD_IDX    (`PCYN_OP_IS_IDX_WIDTH'b00)
`define PCYN_OP_IS_ST_IDX    (`PCYN_OP_IS_IDX_WIDTH'b01)
`define PCYN_OP_IS_BR_IDX    (`PCYN_OP_IS_IDX_WIDTH'b10)
`define PCYN_OP_IS_JL_IDX    (`PCYN_OP_IS_IDX_WIDTH'b11)

// Procyon operations
`define PCYN_OP_WIDTH       5
`define PCYN_OP_SHAMT_WIDTH 5
`define PCYN_OP_ADD         (`PCYN_OP_WIDTH'b00000)
`define PCYN_OP_SUB         (`PCYN_OP_WIDTH'b00001)
`define PCYN_OP_AND         (`PCYN_OP_WIDTH'b00010)
`define PCYN_OP_OR          (`PCYN_OP_WIDTH'b00011)
`define PCYN_OP_XOR         (`PCYN_OP_WIDTH'b00100)
`define PCYN_OP_SLL         (`PCYN_OP_WIDTH'b00101)
`define PCYN_OP_SRL         (`PCYN_OP_WIDTH'b00110)
`define PCYN_OP_SRA         (`PCYN_OP_WIDTH'b00111)
`define PCYN_OP_EQ          (`PCYN_OP_WIDTH'b01000)
`define PCYN_OP_NE          (`PCYN_OP_WIDTH'b01001)
`define PCYN_OP_LT          (`PCYN_OP_WIDTH'b01010)
`define PCYN_OP_LTU         (`PCYN_OP_WIDTH'b01011)
`define PCYN_OP_GE          (`PCYN_OP_WIDTH'b01100)
`define PCYN_OP_GEU         (`PCYN_OP_WIDTH'b01101)
`define PCYN_OP_LB          (`PCYN_OP_WIDTH'b01110)
`define PCYN_OP_LH          (`PCYN_OP_WIDTH'b01111)
`define PCYN_OP_LW          (`PCYN_OP_WIDTH'b10000)
`define PCYN_OP_LBU         (`PCYN_OP_WIDTH'b10001)
`define PCYN_OP_LHU         (`PCYN_OP_WIDTH'b10010)
`define PCYN_OP_SB          (`PCYN_OP_WIDTH'b10011)
`define PCYN_OP_SH          (`PCYN_OP_WIDTH'b10100)
`define PCYN_OP_SW          (`PCYN_OP_WIDTH'b10101)
`define PCYN_OP_FILL        (`PCYN_OP_WIDTH'b10110)
`define PCYN_OP_UNDEFINED   (`PCYN_OP_WIDTH'b11111)

// BIU operations
`define PCYN_BIU_FUNC_WIDTH 2
`define PCYN_BIU_FUNC_READ  (`PCYN_BIU_FUNC_WIDTH'b00)
`define PCYN_BIU_FUNC_WRITE (`PCYN_BIU_FUNC_WIDTH'b01)
`define PCYN_BIU_FUNC_RMW   (`PCYN_BIU_FUNC_WIDTH'b10)

// BIU burst lengths
`define PCYN_BIU_LEN_WIDTH    3
`define PCYN_BIU_LEN_1B       (`PCYN_BIU_LEN_WIDTH'b000)
`define PCYN_BIU_LEN_2B       (`PCYN_BIU_LEN_WIDTH'b001)
`define PCYN_BIU_LEN_4B       (`PCYN_BIU_LEN_WIDTH'b010)
`define PCYN_BIU_LEN_8B       (`PCYN_BIU_LEN_WIDTH'b011)
`define PCYN_BIU_LEN_16B      (`PCYN_BIU_LEN_WIDTH'b100)
`define PCYN_BIU_LEN_32B      (`PCYN_BIU_LEN_WIDTH'b101)
`define PCYN_BIU_LEN_64B      (`PCYN_BIU_LEN_WIDTH'b110)
`define PCYN_BIU_LEN_128B     (`PCYN_BIU_LEN_WIDTH'b111)
`define PCYN_BIU_LEN_MAX      (`PCYN_BIU_LEN_128B)
`define PCYN_BIU_LEN_MAX_SIZE 128

// Wishbone bus Cycle Type Identifiers
`define WB_CTI_WIDTH        3
`define WB_CTI_CLASSIC      (`WB_CTI_WIDTH'b000)
`define WB_CTI_CONSTANT     (`WB_CTI_WIDTH'b001)
`define WB_CTI_INCREMENTING (`WB_CTI_WIDTH'b010)
`define WB_CTI_END_OF_BURST (`WB_CTI_WIDTH'b111)

// Wishbone bus Burst Type Extensions
`define WB_BTE_WIDTH 2
`define WB_BTE_LINEAR (`WB_BTE_WIDTH'b00)
`define WB_BTE_4BEAT  (`WB_BTE_WIDTH'b01)
`define WB_BTE_8BEAT  (`WB_BTE_WIDTH'b10)
`define WB_BTE_16BEAT (`WB_BTE_WIDTH'b11)
