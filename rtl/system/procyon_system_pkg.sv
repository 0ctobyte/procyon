/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

package procyon_system_pkg;
    import procyon_lib_pkg::*;

    // SRAM Constants
    localparam SRAM_DATA_WIDTH = 16;
    localparam SRAM_ADDR_WIDTH = 20;
    localparam SRAM_DATA_SIZE = `PCYN_W2S(SRAM_DATA_WIDTH);
    localparam SRAM_ADDR_SPAN = 2097152; // 2M bytes, or 1M 2-byte words
    typedef logic [SRAM_ADDR_WIDTH-1:0] sram_addr_t;
    typedef logic [SRAM_DATA_WIDTH-1:0] sram_data_t;
    typedef logic [SRAM_DATA_SIZE-1:0] sram_data_select_t;
endpackage: procyon_system_pkg

