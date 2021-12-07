/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

`ifndef _PROCYON_LIB_PKG_SVH_
`define _PROCYON_LIB_PKG_SVH_

package procyon_lib_pkg;
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
endpackage: procyon_lib_pkg

`endif // _PROCYON_LIB_PKG_SVH_
