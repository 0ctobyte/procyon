// Synchronous FIFO
// Dual port FIFO for single clock domains with one read and one write port 
// Accepts a flush signal which will clear the FIFO

module sync_fifo #(
    parameter  DATA_WIDTH = 8,
    parameter  FIFO_DEPTH = 8
) (
    input  logic                  clk,
    input  logic                  n_rst,

    input  logic                  i_flush,

    // FIFO read interface
    input  logic                  i_fifo_rd_en,
    output logic [DATA_WIDTH-1:0] o_fifo_data,
    output logic                  o_fifo_empty,

    // FIFO write interface
    input  logic                  i_fifo_wr_en,
    input  logic [DATA_WIDTH-1:0] i_fifo_data,
    output logic                  o_fifo_full

);
    // Signals for RAM interface
    logic [$clog2(FIFO_DEPTH)-1:0] ram_rd_addr;
    logic [$clog2(FIFO_DEPTH)-1:0] ram_wr_addr;
    logic [DATA_WIDTH-1:0]         ram_rd_data;
    logic [DATA_WIDTH-1:0]         ram_wr_data;
    logic                          ram_rd_en;
    logic                          ram_wr_en;

    // Read and write pointers
    logic [$clog2(FIFO_DEPTH):0]   wr_addr;
    logic [$clog2(FIFO_DEPTH):0]   rd_addr;

    // Enable signals for the rd_addr and wr_addr registers
    logic                          wr_addr_en;
    logic                          rd_addr_en;

    // Empty and full detection logic
    logic                          full;
    logic                          empty;

    assign full          = ({~wr_addr[$clog2(FIFO_DEPTH)], wr_addr[$clog2(FIFO_DEPTH)-1:0]} == rd_addr);
    assign empty         = (wr_addr == rd_addr);

    // Don't update the rd_addr register if the the fifo is empty even if rd_en is asserted
    // Similarly don't update the wr_addr register if the fifo is full even if wr_en is asserted
    assign wr_addr_en    = i_fifo_wr_en & (~full);
    assign rd_addr_en    = i_fifo_rd_en & (~empty);

    // The FIFO memory read/write addresses don't include the MSB since that is only 
    // used to check for overflow (i.e. full) the FIFO entries not actually used to address
    assign ram_wr_addr   = wr_addr[$clog2(FIFO_DEPTH)-1:0];
    assign ram_rd_addr   = rd_addr[$clog2(FIFO_DEPTH)-1:0];

    // The logic is the same for the FIFO RAM enables and the wr/rd addr enables
    assign ram_wr_en     = wr_addr_en;
    assign ram_rd_en     = rd_addr_en;

    // wire up data signals between FIFO and RAM
    assign ram_wr_data   = i_fifo_data;
    assign o_fifo_data   = ram_rd_data;

    // Update the fifo full/empty signals
    assign o_fifo_full   = full;
    assign o_fifo_empty  = empty;

    // Update the wr_addr pointer
    always_ff @(posedge clk, negedge n_rst) begin : WR_ADDR_REG
        if (~n_rst) begin
            wr_addr <= 'b0;
        end else if (i_flush) begin
            wr_addr <= 'b0;
        end else if (wr_addr_en) begin
            wr_addr <= wr_addr + 1'b1;
        end
    end
 
    // Update the rd_addr pointer
    always_ff @(posedge clk, negedge n_rst) begin : RD_ADDR_REG
        if (~n_rst) begin
            rd_addr <= 'b0;
        end else if (i_flush) begin
            rd_addr <= 'b0;
        end else if (rd_addr_en) begin
            rd_addr <= rd_addr + 1'b1;
        end
    end

    // Instantiate RAM for FIFO memory
    dp_ram #(
        .DATA_WIDTH(DATA_WIDTH), 
        .RAM_DEPTH(FIFO_DEPTH), 
        .BASE_ADDR(0)
    ) fifo_mem (
        .clk(clk), 
        .n_rst(n_rst), 
        .i_ram_rd_en(ram_rd_en),
        .i_ram_rd_addr(ram_rd_addr),
        .o_ram_rd_data(ram_rd_data),
        .i_ram_wr_en(ram_wr_en),
        .i_ram_wr_addr(ram_wr_addr),
        .i_ram_wr_data(ram_wr_data)
    ); 
     
endmodule
