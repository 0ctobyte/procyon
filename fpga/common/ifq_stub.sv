/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

module ifq_stub #(
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_IC_LINE_SIZE = 32,
    parameter OPTN_HEX_FILE     = "",
    parameter OPTN_HEX_SIZE     = 0,

    parameter IC_LINE_WIDTH     = OPTN_IC_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    output logic                            o_full,

    input  logic                            i_alloc_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_alloc_addr,
    output logic                            o_fill_en,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_fill_addr,
    output logic [IC_LINE_WIDTH-1:0]        o_fill_data
);

    localparam IC_OFFSET_WIDTH  = $clog2(OPTN_IC_LINE_SIZE);
    localparam HEX_IDX_WIDTH    = $clog2(OPTN_HEX_SIZE);

    logic [IC_LINE_WIDTH-1:0] memory [0:OPTN_HEX_SIZE-1];

    logic [HEX_IDX_WIDTH-1:0] addr;
    logic [IC_LINE_WIDTH-1:0] cacheline;

    assign addr = i_alloc_addr[HEX_IDX_WIDTH+IC_OFFSET_WIDTH-1:IC_OFFSET_WIDTH];
    assign cacheline = memory[addr];

    always_ff @(posedge clk) begin
        if (~n_rst) o_fill_en <= '0;
        else        o_fill_en <= i_alloc_en;
    end

    always_ff @(posedge clk) begin
        o_fill_addr <= {i_alloc_addr[OPTN_ADDR_WIDTH-1:IC_OFFSET_WIDTH], {(IC_OFFSET_WIDTH){1'b0}}};
        o_fill_data <= cacheline;
    end

    assign o_full = 1'b0;

    initial $readmemh(OPTN_HEX_FILE, memory);

endmodule
