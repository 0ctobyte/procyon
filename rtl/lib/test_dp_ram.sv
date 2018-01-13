// Byte addressable RAM with initialized memory

`define TEST_DP_RAM_WORD_SIZE  (DATA_WIDTH/8)

module test_dp_ram #(
    parameter  DATA_WIDTH = 32,
    parameter  RAM_DEPTH  = 8,
    parameter  BASE_ADDR  = 0,
    parameter  RAM_FILE   = ""
) (
    input  logic                                     clk,
    input  logic                                     n_rst,

    // RAM read interface
    input  logic                                     i_ram_rd_en,
    input  logic [$clog2(RAM_DEPTH)-1:0]             i_ram_rd_addr,
    output logic [DATA_WIDTH-1:0]                    o_ram_rd_data,

    // RAM write interface
    input  logic                                     i_ram_wr_en,
    input  logic [`TEST_DP_RAM_WORD_SIZE-1:0]        i_ram_wr_byte_en,
    input  logic [$clog2(RAM_DEPTH)-1:0]             i_ram_wr_addr,
    input  logic [DATA_WIDTH-1:0]                    i_ram_wr_data
);

    // Memory array
    logic [7:0] ram [BASE_ADDR:BASE_ADDR + RAM_DEPTH - 1];

    // Used to check if addresses are within range
    logic cs_wr;
    logic cs_rd;

    assign cs_wr         = (n_rst && i_ram_wr_en && (i_ram_wr_addr >= BASE_ADDR) && (i_ram_wr_addr < (BASE_ADDR + RAM_DEPTH)));
    assign cs_rd         = (n_rst && i_ram_rd_en && (i_ram_rd_addr >= BASE_ADDR) && (i_ram_rd_addr < (BASE_ADDR + RAM_DEPTH)));

    // Asynchronous read; perform read combinationally
    genvar i;
    generate
    for (i = 0; i < `TEST_DP_RAM_WORD_SIZE; i++) begin : ASYNC_RAM_READ
        assign o_ram_rd_data[(i+1)*8-1:i*8] = (cs_rd) ? ram[i_ram_rd_addr + i] : 'b0;
    end
    endgenerate

    // Synchronous write; perform write at positive clock edge
    always_ff @(posedge clk) begin
        for (int i = 0; i < `TEST_DP_RAM_WORD_SIZE; i++) begin : SYNC_RAM_WRITE
            if (cs_wr && i_ram_wr_byte_en[i]) begin
                ram[i_ram_wr_addr+i]   <= i_ram_wr_data[i*8 +: 8];
            end
        end
    end

    initial begin
        $readmemh(RAM_FILE, ram);
    end

endmodule
