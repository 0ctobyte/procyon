/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Byte addressable RAM with initialized memory

module procyon_ram_dp_test #(
    parameter  OPTN_DATA_WIDTH = 32,
    parameter  OPTN_RAM_DEPTH  = 8,
    parameter  OPTN_BASE_ADDR  = 0,
    parameter  OPTN_RAM_FILE   = "",

    parameter RAM_IDX_WIDTH    = $clog2(OPTN_RAM_DEPTH),
    parameter DATA_SIZE        = OPTN_DATA_WIDTH / 8
)(
    input  logic                       clk,
    input  logic                       n_rst,

    // RAM read interface
    input  logic                       i_ram_rd_en,
    input  logic [RAM_IDX_WIDTH-1:0]   i_ram_rd_addr,
    output logic [OPTN_DATA_WIDTH-1:0] o_ram_rd_data,

    // RAM write interface
    input  logic                       i_ram_wr_en,
    input  logic [DATA_SIZE-1:0]       i_ram_wr_byte_en,
    input  logic [RAM_IDX_WIDTH-1:0]   i_ram_wr_addr,
    input  logic [OPTN_DATA_WIDTH-1:0] i_ram_wr_data
);

    // Memory array
    logic [7:0] ram [OPTN_BASE_ADDR:OPTN_BASE_ADDR + OPTN_RAM_DEPTH - 1];

    // Used to check if addresses are within range
    logic cs_wr;
    logic cs_rd;

    assign cs_wr = n_rst && i_ram_wr_en;
    assign cs_rd = n_rst && i_ram_rd_en;

    genvar i;
    generate
    // Asynchronous read; perform read combinationally
    for (i = 0; i < DATA_SIZE; i++) begin : GEN_ASYNC_RAM_READ
        assign o_ram_rd_data[i*8 +: 8] = cs_rd ? ram[i_ram_rd_addr + i] : 8'b0;
    end

    // Synchronous write; perform write at positive clock edge
    for (i = 0; i < DATA_SIZE; i++) begin : GEN_SYNC_RAM_WRITE
        logic ram_wr_byte_en;
        assign ram_wr_byte_en = cs_wr && i_ram_wr_byte_en[i];
        procyon_ff #(8) ram_ff (.clk(clk), .i_en(ram_wr_byte_en), .i_d(i_ram_wr_data[i*8 +: 8]), .o_q(ram[i_ram_wr_addr+i]));
    end
    endgenerate

    initial $readmemh(OPTN_RAM_FILE, ram);

endmodule
