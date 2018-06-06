`include "../../rtl/core/common.svh"

import procyon_types::*;

module boot_rom #(
    parameter HEX_FILE = ""
) (
    output procyon_data_t  o_ic_insn,
    output logic           o_ic_valid,
    input  procyon_addr_t  i_ic_pc,
    input  logic           i_ic_en
);

    localparam MEM_SIZE = 2048;

    logic [7:0] memory [0:MEM_SIZE-1];

    logic [$clog2(MEM_SIZE)-1:0] addr;

    assign addr = i_ic_pc[$clog2(MEM_SIZE)-1:0];
    assign o_ic_valid = i_ic_en;
    assign o_ic_insn[7:0]   = memory[addr];
    assign o_ic_insn[15:8]  = memory[addr + 1];
    assign o_ic_insn[23:16] = memory[addr + 2];
    assign o_ic_insn[31:24] = memory[addr + 3];

    initial begin
        $readmemh(HEX_FILE, memory);
    end

endmodule
