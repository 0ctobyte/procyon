/* 
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDS-License-Identifier: MIT
 */

// Simple Dual Port RAM with bypassing

module procyon_ram_sdpb #(
    parameter OPTN_DATA_WIDTH = 8,
    parameter OPTN_RAM_DEPTH  = 8,

    parameter RAM_IDX_WIDTH   = $clog2(OPTN_RAM_DEPTH)
) (
    input  logic                       clk,

    // RAM interface
    input  logic                       i_ram_we,
    input  logic                       i_ram_re,
    input  logic [RAM_IDX_WIDTH-1:0]   i_ram_addr_r,
    input  logic [RAM_IDX_WIDTH-1:0]   i_ram_addr_w,
    input  logic [OPTN_DATA_WIDTH-1:0] i_ram_data,
    output logic [OPTN_DATA_WIDTH-1:0] o_ram_data
);

    logic [OPTN_DATA_WIDTH-1:0] ram [0:OPTN_RAM_DEPTH-1];

    // Synchronous write
    always_ff @(posedge clk) begin
        if (i_ram_we) ram[i_ram_addr_w] <= i_ram_data;
    end

    // Synchronous read
    always_ff @(posedge clk) begin
        if (i_ram_re) o_ram_data <= (i_ram_addr_r == i_ram_addr_w) & i_ram_we ? i_ram_data : ram[i_ram_addr_r];
    end

endmodule
