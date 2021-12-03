/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

module ifq_stub #(
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_IC_LINE_SIZE = 32,
    parameter OPTN_HEX_SIZE     = 0,

    parameter IC_LINE_WIDTH     = OPTN_IC_LINE_SIZE * 8,
    parameter ROM_ADDR_WIDTH    = OPTN_HEX_SIZE == 1 ? 1 : $clog2(OPTN_HEX_SIZE)
)(
    input  logic                            clk,
    input  logic                            n_rst,

    output logic                            o_full,

    // ROM interface
    input  logic [IC_LINE_WIDTH-1:0]        i_rom_data,
    output logic [ROM_ADDR_WIDTH-1:0]       o_rom_addr,

    input  logic                            i_alloc_en,
/* verilator lint_off UNUSED */
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_alloc_addr,
/* verilator lint_on  UNUSED */
    output logic                            o_fill_en,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_fill_addr,
    output logic [IC_LINE_WIDTH-1:0]        o_fill_data
);

    localparam IC_OFFSET_WIDTH = $clog2(OPTN_IC_LINE_SIZE);

    assign o_rom_addr = i_alloc_addr[ROM_ADDR_WIDTH+IC_OFFSET_WIDTH-1:IC_OFFSET_WIDTH];

    always_ff @(posedge clk) begin
        if (~n_rst) o_fill_en <= '0;
        else        o_fill_en <= i_alloc_en;
    end

    always_ff @(posedge clk) begin
        o_fill_addr <= {i_alloc_addr[OPTN_ADDR_WIDTH-1:IC_OFFSET_WIDTH], {(IC_OFFSET_WIDTH){1'b0}}};
        o_fill_data <= i_rom_data;
    end

    assign o_full = 1'b0;

endmodule
