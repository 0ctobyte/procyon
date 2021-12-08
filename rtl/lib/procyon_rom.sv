/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// ROM with initialized memory

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_rom #(
    parameter OPTN_DATA_WIDTH = 8,
    parameter OPTN_ROM_DEPTH  = 8,
    parameter OPTN_ROM_FILE   = ""
)(
    // ROM interface
    input  logic [`PCYN_C2I(OPTN_ROM_DEPTH)-1:0] i_rom_addr,
    output logic [OPTN_DATA_WIDTH-1:0]           o_rom_data
);

    // Memory array
    logic [OPTN_DATA_WIDTH-1:0] rom [0:OPTN_ROM_DEPTH - 1];

    // Asynchronous read; perform read combinationally
    assign o_rom_data = rom[i_rom_addr];

    initial $readmemh(OPTN_ROM_FILE, rom);

endmodule
