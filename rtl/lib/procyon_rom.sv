/*
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// ROM with initialized memory

module procyon_rom #(
    parameter OPTN_DATA_WIDTH = 8,
    parameter OPTN_ROM_DEPTH  = 8,
    parameter OPTN_BASE_ADDR  = 0,
    parameter OPTN_ROM_FILE   = "",

    parameter ROM_IDX_WIDTH   = $clog2(OPTN_ROM_DEPTH)
) (
    input  logic                       clk,
    input  logic                       n_rst,

    // ROM interface
    input  logic [ROM_IDX_WIDTH-1:0]   i_rom_rd_addr,
    output logic [OPTN_DATA_WIDTH-1:0] o_rom_data_out
);

    // Memory array
    logic [OPTN_DATA_WIDTH-1:0] rom [OPTN_BASE_ADDR:OPTN_BASE_ADDR + OPTN_ROM_DEPTH - 1];

    // Used to check if addresses are within range
    logic cs;

    assign cs         = (n_rst && (i_rom_rd_addr >= OPTN_BASE_ADDR) && (i_rom_rd_addr < (OPTN_BASE_ADDR + OPTN_ROM_DEPTH)));

    // Asynchronous read; perform read combinationally
    assign o_rom_data_out = (cs) ? rom[i_rom_rd_addr] : 'b0;

    initial begin
        $readmemh(OPTN_ROM_FILE, rom);
    end

endmodule
