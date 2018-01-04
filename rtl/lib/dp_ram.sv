// Dual Port RAM
// 1 asynchronous read port and 1 synchronous write port

module dp_ram #(
    parameter DATA_WIDTH = 8,
    parameter RAM_DEPTH  = 8,
    parameter BASE_ADDR  = 0
) (
    input  logic     clk,
    input  logic     n_rst,

    // RAM interface
    dp_ram_rd_if.ram if_dp_ram_rd,
    dp_ram_wr_if.ram if_dp_ram_wr
);

    // Memory array
    logic [DATA_WIDTH-1:0] ram [BASE_ADDR:BASE_ADDR + RAM_DEPTH - 1];

    // Used to check if addresses are within range
    logic cs_wr;
    logic cs_rd;

    assign cs_wr = (n_rst && if_dp_ram_wr.en && (if_dp_ram_wr.addr >= BASE_ADDR) && (if_dp_ram_wr.addr < (BASE_ADDR + RAM_DEPTH)));
    assign cs_rd = (n_rst && if_dp_ram_rd.en && (if_dp_ram_rd.addr >= BASE_ADDR) && (if_dp_ram_rd.addr < (BASE_ADDR + RAM_DEPTH)));

    // Asynchronous read; perform read combinationally 
    assign if_dp_ram_rd.data = (cs_rd) ? ram[if_dp_ram_rd.addr] : 'b0;

    // Synchronous write; perform write at positive clock edge
    always_ff @(posedge clk) begin : RAM_WRITE
        if (cs_wr) begin
            ram[if_dp_ram_wr.addr] <= if_dp_ram_wr.data;
        end 
    end

endmodule
