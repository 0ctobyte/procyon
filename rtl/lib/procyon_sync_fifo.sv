// Synchronous FIFO

module procyon_sync_fifo #(
    parameter OPTN_DATA_WIDTH = 8,
    parameter OPTN_FIFO_DEPTH = 8
) (
    input  logic                       clk,
    input  logic                       n_rst,

    input  logic                       i_flush,

    // FIFO read interface
    input  logic                       i_fifo_ack,
    output logic [OPTN_DATA_WIDTH-1:0] o_fifo_data,
    output logic                       o_fifo_valid,

    // FIFO write interface
    input  logic                       i_fifo_we,
    input  logic [OPTN_DATA_WIDTH-1:0] i_fifo_data,
    output logic                       o_fifo_full
);

    localparam FIFO_IDX_WIDTH = $clog2(OPTN_FIFO_DEPTH);

    logic                      fifo_full;
    logic                      fifo_empty;
    logic                      fifo_full_next;
    logic                      fifo_empty_next;
    logic                      ram_we;
    logic [FIFO_IDX_WIDTH-1:0] ram_addr_r;
    logic [FIFO_IDX_WIDTH-1:0] ram_addr_w;
    logic [FIFO_IDX_WIDTH:0]   fifo_head;
    logic [FIFO_IDX_WIDTH:0]   fifo_tail;
    logic [FIFO_IDX_WIDTH:0]   fifo_head_next;
    logic [FIFO_IDX_WIDTH:0]   fifo_tail_next;
    logic                      fifo_ack;
    logic                      fifo_clear;

    assign fifo_clear             = ~n_rst | i_flush;

    assign fifo_head_next         = fifo_ack ? fifo_head + 1'b1 : fifo_head;
    assign fifo_tail_next         = ram_we ? fifo_tail + 1'b1 : fifo_tail;
    assign fifo_full_next         = {~fifo_tail_next[FIFO_IDX_WIDTH], fifo_tail_next[FIFO_IDX_WIDTH-1:0]} == fifo_head_next;
    assign fifo_empty_next        = fifo_tail_next == fifo_head_next;
    assign fifo_ack               = ~fifo_empty & i_fifo_ack;

    assign ram_we                 = ~fifo_full & i_fifo_we;
    assign ram_addr_r             = fifo_head[$bits(ram_addr_r)-1:0];
    assign ram_addr_w             = fifo_tail[$bits(ram_addr_w)-1:0];

    assign o_fifo_full            = fifo_full;

    always_ff @(posedge clk) begin
        if (fifo_clear) begin
            fifo_full    <= 1'b0;
            fifo_empty   <= 1'b1;
            o_fifo_valid <= 1'b0;
        end else begin
            fifo_full    <= fifo_full_next;
            fifo_empty   <= fifo_empty_next;
            o_fifo_valid <= ~fifo_empty;
        end
    end

    always_ff @(posedge clk) begin
        if (fifo_clear)  fifo_tail <= {(FIFO_IDX_WIDTH+1){1'b0}};
        else if (ram_we) fifo_tail <= fifo_tail + 1'b1;
    end

    always_ff @(posedge clk) begin
        if (fifo_clear)    fifo_head <= {(FIFO_IDX_WIDTH+1){1'b0}};
        else if (fifo_ack) fifo_head <= fifo_head + 1'b1;
    end

    procyon_ram_sdpb #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_RAM_DEPTH(OPTN_FIFO_DEPTH)
    ) fifo_mem (
        .clk(clk),
        .i_ram_we(ram_we),
        .i_ram_re(fifo_ack),
        .i_ram_addr_r(ram_addr_r),
        .i_ram_addr_w(ram_addr_w),
        .i_ram_data(i_fifo_data),
        .o_ram_data(o_fifo_data)
    );

endmodule
