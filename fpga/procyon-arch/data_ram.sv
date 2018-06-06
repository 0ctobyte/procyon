`include "../../rtl/core/common.svh"

import procyon_types::*;

module data_ram #(
    parameter HEX_FILE = ""
) (
    input  logic                  clk,

    output logic                  o_dc_hit,
    output procyon_data_t         o_dc_data,
    input  logic                  i_dc_we,
    input  procyon_addr_t         i_dc_addr,
    input  procyon_data_t         i_dc_data,
    input  procyon_byte_select_t  i_dc_byte_select
);

    localparam MEM_SIZE = 64;

    logic [7:0] memory [0:MEM_SIZE-1];

    logic [$clog2(MEM_SIZE)-1:0] dc_addr;

    assign dc_addr             = i_dc_addr[$clog2(MEM_SIZE)-1:0];

    // FIXME: Temporary data cache interface
    assign o_dc_hit            = 1'b1;
    assign o_dc_data[7:0]      = memory[dc_addr];
    assign o_dc_data[15:8]     = memory[dc_addr + 1];
    assign o_dc_data[23:16]    = memory[dc_addr + 2];
    assign o_dc_data[31:24]    = memory[dc_addr + 3];

    initial begin
        $readmemh(HEX_FILE, memory);
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
