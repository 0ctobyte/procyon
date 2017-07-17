// ROM with initialized memory 

module rom #(
    parameter DATA_WIDTH = 8,
    parameter ROM_DEPTH  = 8,
    parameter BASE_ADDR  = 0,
    parameter ROM_FILE   = ""
) (
    input  logic                         clk,
    input  logic                         n_rst,

    // ROM interface
    input  logic [$clog2(ROM_DEPTH)-1:0] i_rd_addr,
    output logic [DATA_WIDTH-1:0]        o_data_out
);

    // Memory array
    logic [DATA_WIDTH-1:0] rom [BASE_ADDR:BASE_ADDR + ROM_DEPTH - 1];

    // Used to check if addresses are within range
    logic cs;

    assign cs = (n_rst && (i_rd_addr >= BASE_ADDR) && (i_rd_addr < (BASE_ADDR + ROM_DEPTH)));

    // Asynchronous read; perform read combinationally 
    assign o_data_out = (cs) ? rom[i_rd_addr] : 'b0;

    initial begin
        $readmemh(ROM_FILE, rom);
    end

endmodule
