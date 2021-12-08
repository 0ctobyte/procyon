/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Simple Dual Port RAM with bypassing

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_ram_sdpb #(
    parameter OPTN_DATA_WIDTH = 8,
    parameter OPTN_RAM_DEPTH  = 8
)(
    input  logic                                 clk,

    // RAM read interface
    input  logic                                 i_ram_rd_en,
    input  logic [`PCYN_C2I(OPTN_RAM_DEPTH)-1:0] i_ram_rd_addr,
    output logic [OPTN_DATA_WIDTH-1:0]           o_ram_rd_data,

    // RAM write interface
    input  logic                                 i_ram_wr_en,
    input  logic [`PCYN_C2I(OPTN_RAM_DEPTH)-1:0] i_ram_wr_addr,
    input  logic [OPTN_DATA_WIDTH-1:0]           i_ram_wr_data
);

    logic [OPTN_DATA_WIDTH-1:0] ram [0:OPTN_RAM_DEPTH-1];

    // Synchronous write
    always_ff @(posedge clk) if (i_ram_wr_en) ram[i_ram_wr_addr] <= i_ram_wr_data;

    // Synchronous read; bypass write data on same cycle to the same address
    logic ram_rd_bypass_sel;
    assign ram_rd_bypass_sel = (i_ram_rd_addr == i_ram_wr_addr) && i_ram_wr_en;
    always_ff @(posedge clk) if (i_ram_rd_en) o_ram_rd_data <= ram_rd_bypass_sel ? i_ram_wr_data : ram[i_ram_rd_addr];

endmodule
