// Dual Port RAM
// 1 asynchronous read port and 1 synchronous write port

module dp_ram #(
    parameter OPTN_DATA_WIDTH = 8,
    parameter OPTN_RAM_DEPTH  = 8,

    localparam RAM_IDX_WIDTH  = $clog2(OPTN_RAM_DEPTH)
) (
    input  logic                       clk,
    input  logic                       n_rst,

    // RAM read interface
    input  logic                       i_ram_rd_en,
    input  logic [RAM_IDX_WIDTH-1:0]   i_ram_rd_addr,
    output logic [OPTN_DATA_WIDTH-1:0] o_ram_rd_data,

    // RAM write interface
    input  logic                       i_ram_wr_en,
    input  logic [RAM_IDX_WIDTH-1:0]   i_ram_wr_addr,
    input  logic [OPTN_DATA_WIDTH-1:0  i_ram_wr_data
);

    // Memory array
    logic [OPTN_DATA_WIDTH-1:0] ram [0:OPTN_RAM_DEPTH-1];

    // Used to check if addresses are within range
    logic                  cs_wr;
    logic                  cs_rd;

    assign cs_wr         = n_rst && i_ram_wr_en;
    assign cs_rd         = n_rst && i_ram_rd_en;

    // Asynchronous read; perform read combinationally
    assign o_ram_rd_data = (cs_rd) ? ram[i_ram_rd_addr] : {{(OPTN_DATA_WIDTH){1'b0}}};

    // Synchronous write; perform write at positive clock edge
    always_ff @(posedge clk) begin
        if (cs_wr) begin
            ram[i_ram_wr_addr] <= i_ram_wr_data;
        end
    end

endmodule
