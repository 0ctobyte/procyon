/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Wishbone Bus Interface Unit Responder
// This module is the interface to the Wishbone Bus, it can only receive and respond to requests.

// WISHBONE DATASHEET
// Description:                     Wishbone interface responder
// Wishbone rev:                    B4
// Supported Cycles:                Register feedback burst read/write
// CTI support:                     Classic, Incrementing Burst, End of Burst
// BTE support:                     Linear only
// Data port size:                  parameterized: 16-bit, 32-bit, 64-bit supported
// Data port granularity:           8-bit
// Data port max operand size:      8-bit
// Data ordering:                   Little Endian
// Data sequence:                   Undefined
// Clock constraints:               None
// Wishbone signals mapping:
// i_wb_clk   -> CLK_I
// i_wb_rst   -> RST_I
// i_wb_cyc   -> CYC_I
// i_wb_stb   -> STB_I
// i_wb_we    -> WE_I
// i_wb_cti   -> CTI_I()
// i_wb_bte   -> BTE_I()
// i_wb_sel   -> SEL_I()
// i_wb_addr  -> ADR_I()
// i_wb_data  -> DAT_I()
// o_wb_ack   -> ACK_O
// o_wb_data  -> DAT_O()

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_biu_responder_wb #(
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_WB_DATA_WIDTH = 16,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_BASE_ADDR     = 0
)(
    // Wishbone Interface
/* verilator lint_off UNUSED */
    input       logic                                     i_wb_clk,
/* verilator lint_on  UNUSED */
    input       logic                                     i_wb_rst,
    input       logic                                     i_wb_cyc,
    input       logic                                     i_wb_stb,
    input       logic                                     i_wb_we,
    input       wb_cti_t                                  i_wb_cti,
/* verilator lint_off UNUSED */
    input       wb_bte_t                                  i_wb_bte,
/* verilator lint_on  UNUSED */
    input       logic [`PCYN_W2S(OPTN_WB_DATA_WIDTH)-1:0] i_wb_sel,
    input       logic [OPTN_WB_ADDR_WIDTH-1:0]            i_wb_addr,
    input       logic [OPTN_WB_DATA_WIDTH-1:0]            i_wb_data,
    output wire logic [OPTN_WB_DATA_WIDTH-1:0]            o_wb_data,
    output wire logic                                     o_wb_ack,

    // BIU request interface
    input  logic                                          i_biu_done,
    input  logic [OPTN_WB_DATA_WIDTH-1:0]                 i_biu_data,
    output logic                                          o_biu_en,
    output logic                                          o_biu_we,
    output logic                                          o_biu_eob,
    output logic [`PCYN_W2S(OPTN_WB_DATA_WIDTH)-1:0]      o_biu_sel,
    output logic [OPTN_ADDR_WIDTH-1:0]                    o_biu_addr,
    output logic [OPTN_WB_DATA_WIDTH-1:0]                 o_biu_data
);

    localparam WB_DATA_SIZE = `PCYN_W2S(OPTN_WB_DATA_WIDTH);

    // Qualify the write enable with a valid bus cycle
    logic wb_en;
    logic wb_we;
    logic wb_cti_eob;

    assign wb_en = i_wb_cyc & i_wb_stb & ~i_wb_rst;
    assign wb_we = wb_en & i_wb_we;
    assign wb_cti_eob = (i_wb_cti == WB_CTI_END_OF_BURST);

    // Output to BIU interface
    assign o_biu_en = wb_en;
    assign o_biu_we = wb_we;
    assign o_biu_eob = wb_cti_eob;
    assign o_biu_sel = i_wb_sel;
    assign o_biu_addr = i_wb_addr;
    assign o_biu_data = i_wb_data;

    // Output to wishbone bus
    assign o_wb_ack = i_biu_done;
    assign o_wb_data = i_biu_data;

endmodule
