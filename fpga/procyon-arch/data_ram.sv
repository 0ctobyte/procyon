/*
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

module data_ram #(
    parameter OPTN_DATA_WIDTH = 32,
    parameter OPTN_ADDR_WIDTH = 32,
    parameter OPTN_HEX_FILE   = "",

    parameter DATA_SIZE       = OPTN_DATA_WIDTH / 8
) (
    input  logic                       clk,

    output logic                       o_dc_hit,
    output logic [OPTN_DATA_WIDTH-1:0] o_dc_data,
    input  logic                       i_dc_we,
    input  logic [OPTN_ADDR_WIDTH-1:0] i_dc_addr,
    input  logic [OPTN_DATA_WIDTH-1:0] i_dc_data,
    input  logic [DATA_SIZE-1:0]       i_dc_byte_select
);

    localparam MEM_SIZE      = 64;
    localparam MEM_IDX_WIDTH = $clog2(MEM_SIZE);

    logic [7:0]                  memory [0:MEM_SIZE-1];
    logic [$clog2(MEM_SIZE)-1:0] dc_addr;

    assign dc_addr          = i_dc_addr[MEM_IDX_WIDTH-1:0];

    // FIXME: Temporary data cache interface
    assign o_dc_hit         = 1'b1;
    assign o_dc_data[7:0]   = memory[dc_addr];
    assign o_dc_data[15:8]  = memory[dc_addr + 1];
    assign o_dc_data[23:16] = memory[dc_addr + 2];
    assign o_dc_data[31:24] = memory[dc_addr + 3];

    initial begin
        $readmemh(OPTN_HEX_FILE, memory);
    end

    always @(posedge clk) begin
        if (i_dc_we) begin
            memory[dc_addr]     <= i_dc_byte_select[0] ? i_dc_data[7:0]   : memory[dc_addr];
            memory[dc_addr + 1] <= i_dc_byte_select[1] ? i_dc_data[15:8]  : memory[dc_addr + 1];
            memory[dc_addr + 2] <= i_dc_byte_select[2] ? i_dc_data[23:16] : memory[dc_addr + 2];
            memory[dc_addr + 3] <= i_dc_byte_select[3] ? i_dc_data[31:24] : memory[dc_addr + 3];
        end
    end

endmodule
