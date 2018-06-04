`include "../../rtl/core/common.svh"

import procyon_types::*;

module data_ram #(
    parameter HEX_FILE = ""
) (
    input  logic                  clk,

    output logic                  o_dc_hit,
    output procyon_data_t         o_dc_rdata,
    input  logic                  i_dc_re,
    input  procyon_addr_t         i_dc_addr,

    output logic                  o_sq_retire_dc_hit,
    output logic                  o_sq_retire_msq_full,
    input  logic                  i_sq_retire_en,
    input  procyon_byte_select_t  i_sq_retire_byte_en,
    input  procyon_addr_t         i_sq_retire_addr,
    input  procyon_data_t         i_sq_retire_data

);
    
    localparam MEM_SIZE = 64;

    logic [7:0] memory [0:MEM_SIZE-1];

    logic [$clog2(MEM_SIZE)-1:0] dc_addr;
    logic [$clog2(MEM_SIZE)-1:0] sq_retire_addr;

    assign dc_addr              = i_dc_addr[$clog2(MEM_SIZE)-1:0];
    assign sq_retire_addr       = i_sq_retire_addr[$clog2(MEM_SIZE)-1:0];

    // FIXME: Temporary data cache interface
    assign o_dc_hit             = i_dc_re;
    assign o_dc_rdata[7:0]      = memory[dc_addr];
    assign o_dc_rdata[15:8]     = memory[dc_addr + 1];
    assign o_dc_rdata[23:16]    = memory[dc_addr + 2];
    assign o_dc_rdata[31:24]    = memory[dc_addr + 3];

    // FIXME: Temporary store retire to cache interface
    assign o_sq_retire_dc_hit   = i_sq_retire_en ? 1'b1 : 1'b0;
    assign o_sq_retire_msq_full = 1'b0;

    initial begin
        $readmemh(HEX_FILE, memory);
    end

    always @(posedge clk) begin
        if (i_sq_retire_en) begin
            memory[sq_retire_addr]     <= i_sq_retire_byte_en[0] ? i_sq_retire_data[7:0]   : memory[sq_retire_addr];
            memory[sq_retire_addr + 1] <= i_sq_retire_byte_en[1] ? i_sq_retire_data[15:8]  : memory[sq_retire_addr + 1];
            memory[sq_retire_addr + 2] <= i_sq_retire_byte_en[2] ? i_sq_retire_data[23:16] : memory[sq_retire_addr + 2];
            memory[sq_retire_addr + 3] <= i_sq_retire_byte_en[3] ? i_sq_retire_data[31:24] : memory[sq_retire_addr + 3];
        end
    end

endmodule
