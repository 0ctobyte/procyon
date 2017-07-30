// Synchronous FIFO
// Dual port FIFO for single clock domains with one read and one write port 
// Accepts a flush signal which will clear the FIFO

module sync_fifo #(
    parameter  DATA_WIDTH = 8,
    parameter  FIFO_DEPTH = 8
) (
    input  logic clk,
    input  logic n_rst,

    input  logic i_flush,

    // FIFO interface
    fifo_wr_if.fifo if_fifo_wr,
    fifo_rd_if.fifo if_fifo_rd
);

    // RAM interface
    dp_ram_if #(
        .DATA_WIDTH(DATA_WIDTH),
        .RAM_DEPTH(FIFO_DEPTH)
    ) if_dp_ram (); 

    localparam LOG2_FIFO_DEPTH = $clog2(FIFO_DEPTH);

    // Read and write pointers
    logic [LOG2_FIFO_DEPTH:0] wr_addr;
    logic [LOG2_FIFO_DEPTH:0] rd_addr;

    // Enable signals for the rd_addr and wr_addr registers
    logic wr_addr_en;
    logic rd_addr_en;

    // Don't update the rd_addr register if the the fifo is empty even if rd_en is asserted
    // Similarly don't update the wr_addr register if the fifo is full even if wr_en is asserted
    assign wr_addr_en = if_fifo_wr.wr_en & (~if_fifo_wr.full);
    assign rd_addr_en = if_fifo_rd.rd_en & (~if_fifo_rd.empty);

    // The FIFO memory read/write addresses don't include the MSB since that is only 
    // used to check for overflow (i.e. if_fifo.full) the FIFO entries not actually used to address
    assign if_dp_ram.wr_addr = wr_addr[LOG2_FIFO_DEPTH-1:0];
    assign if_dp_ram.rd_addr = rd_addr[LOG2_FIFO_DEPTH-1:0];

    // The logic is the same for the FIFO RAM enables and the wr/rd addr enables
    assign if_dp_ram.wr_en = wr_addr_en;
    assign if_dp_ram.rd_en = rd_addr_en;

    // wire up data signals between FIFO and RAM
    assign if_dp_ram.data_in = if_fifo_wr.data_in;
    assign if_fifo_rd.data_out  = if_dp_ram.data_out;

    // Update the fifo full/empty signals
    assign if_fifo_wr.full  = ({~wr_addr[LOG2_FIFO_DEPTH], wr_addr[LOG2_FIFO_DEPTH-1:0]} == rd_addr);
    assign if_fifo_rd.empty = (wr_addr == rd_addr);

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
        .if_dp_ram(if_dp_ram)
    ); 
     
endmodule
