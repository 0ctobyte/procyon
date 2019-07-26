module boot_rom #(
    parameter OPTN_DATA_WIDTH = 32,
    parameter OPTN_ADDR_WIDTH = 32,
    parameter OPTN_HEX_FILE   = "",
    parameter OPTN_HEX_SIZE   = 0
)(
    output logic [OPTN_DATA_WIDTH-1:0] o_ic_insn,
    output logic                       o_ic_valid,
    input  logic [OPTN_ADDR_WIDTH-1:0] i_ic_pc,
    input  logic                       i_ic_en
);

    localparam HEX_IDX_WIDTH = $clog2(OPTN_HEX_SIZE);

    logic [7:0]               memory [0:OPTN_HEX_SIZE-1];
    logic [HEX_IDX_WIDTH-1:0] addr;

    assign addr             = i_ic_pc[HEX_IDX_WIDTH-1:0];
    assign o_ic_valid       = i_ic_en;
    assign o_ic_insn[7:0]   = memory[addr];
    assign o_ic_insn[15:8]  = memory[addr + 1];
    assign o_ic_insn[23:16] = memory[addr + 2];
    assign o_ic_insn[31:24] = memory[addr + 3];

    initial begin
        $readmemh(OPTN_HEX_FILE, memory);
    end

endmodule
