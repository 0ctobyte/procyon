// SRAM controller with a wishbone interface
// Controls the IS61WV102416BLL SRAM chip

`define SRAM_DATA_WIDTH 16
`define SRAM_ADDR_WIDTH 20
`define SRAM_WORD_SIZE  (`SRAM_DATA_WIDTH/8)
`define SRAM_ADDR_SPAN  2097152 // 2M bytes, or 1M 2-byte words

module wb_sram #(
    parameter  DATA_WIDTH      = 16,
    parameter  ADDR_WIDTH      = 32,
    parameter  BASE_ADDR       = 0,
    parameter  FIFO_DEPTH      = 8
) (
    // Wishbone Interface
    input  logic                             i_wb_clk,     // CLK_I
    input  logic                             i_wb_rst,     // RST_I
    input  logic                             i_wb_cyc,     // CYC_I
    input  logic                             i_wb_stb,     // STB_I
    input  logic                             i_wb_we,      // WE_I
    input  logic [DATA_WIDTH/8-1:0]          i_wb_sel,     // SEL_I
    input  logic [ADDR_WIDTH-1:0]            i_wb_addr,    // ADR_I
    input  logic [DATA_WIDTH-1:0]            i_wb_data,    // DAT_I
    output logic [DATA_WIDTH-1:0]            o_wb_data,    // DAT_O
    output logic                             o_wb_ack,     // ACK_O
    output logic                             o_wb_stall,   // STALL_O

    // SRAM interface
    inout  wire  [`SRAM_DATA_WIDTH-1:0]      io_sram_dq,
    output logic [`SRAM_ADDR_WIDTH-1:0]      o_sram_addr,
    output logic                             o_sram_ce_n,
    output logic                             o_sram_oe_n,
    output logic                             o_sram_we_n,
    output logic                             o_sram_ub_n,
    output logic                             o_sram_lb_n
);

    localparam WORD_SIZE       = DATA_WIDTH/8;
    localparam FIFO_DATA_WIDTH = `SRAM_DATA_WIDTH+`SRAM_ADDR_WIDTH+1+`SRAM_WORD_SIZE+1;

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        ACK0 = 2'b01,
        ACK1 = 2'b10
    } state_t;

    state_t                      state;
    state_t                      state_q;

    logic                        unaligned;
    logic                        cs;
    logic                        n_rst;

    logic                        wb_slave_fifo_flush;
    logic                        wb_slave_fifo_rd_en;
    logic                        wb_slave_fifo_wr_en;
    logic                        wb_slave_fifo_empty;
    logic                        wb_slave_fifo_full;
    logic [FIFO_DATA_WIDTH-1:0]  wb_slave_fifo_rd_data;
    logic [FIFO_DATA_WIDTH-1:0]  wb_slave_fifo_wr_data;

    logic [`SRAM_DATA_WIDTH-1:0] sram_data;
    logic [`SRAM_ADDR_WIDTH:0]   sram_addr;
    logic [`SRAM_WORD_SIZE-1:0]  sram_sel;
    logic                        sram_we;

    logic [7:0]                  sram_data_q;
    logic [`SRAM_ADDR_WIDTH:0]   sram_addr_q;
    logic [`SRAM_WORD_SIZE-1:0]  sram_sel_q;
    logic                        sram_we_q;

    assign n_rst                 = ~i_wb_rst;
    assign cs                    = (i_wb_addr >= BASE_ADDR) && (i_wb_addr < (BASE_ADDR+`SRAM_ADDR_SPAN));

    // Wire up FIFO interface, stall if FIFO is full, flush FIFO if there is
    // no valid bus cycle but the FIFO is not empty
    assign wb_slave_fifo_flush   = ~wb_slave_fifo_empty && ~i_wb_cyc;
    assign wb_slave_fifo_wr_data = {i_wb_data[`SRAM_DATA_WIDTH-1:0], i_wb_addr[`SRAM_ADDR_WIDTH:0], i_wb_sel[`SRAM_WORD_SIZE-1:0], i_wb_we};
    assign wb_slave_fifo_wr_en   = i_wb_cyc && i_wb_stb && cs;
    assign wb_slave_fifo_rd_en   = state_q == ACK0;
    assign o_wb_stall            = wb_slave_fifo_full;

    // Pull out signals from FIFO
    assign sram_data             = wb_slave_fifo_rd_data[FIFO_DATA_WIDTH-1:FIFO_DATA_WIDTH-`SRAM_DATA_WIDTH];
    assign sram_addr             = wb_slave_fifo_rd_data[`SRAM_ADDR_WIDTH+`SRAM_WORD_SIZE+1:`SRAM_WORD_SIZE+1];
    assign sram_sel              = wb_slave_fifo_rd_data[`SRAM_WORD_SIZE:1];
    assign sram_we               = wb_slave_fifo_rd_data[0];
    assign unaligned             = sram_addr[0];

    // Assign SRAM outputs
    assign o_sram_ce_n           = 1'b0;
    assign o_sram_oe_n           = 1'b0;
    assign io_sram_dq            = (state_q == ACK0 && sram_we) ? (unaligned ? {sram_data[7:0], 8'b0} : sram_data) :
                                   (state_q == ACK1 && sram_we_q) ? {8'b0, sram_data_q} :
                                   {{(`SRAM_DATA_WIDTH){1'bz}}};

    // Latch sram data, addr, we and select signals for unaligned case
    always_ff @(posedge i_wb_clk) begin
        if (state_q == ACK0) begin
            sram_data_q <= sram_we ? sram_data[`SRAM_DATA_WIDTH-1:8] : io_sram_dq[`SRAM_DATA_WIDTH-1:8];
            sram_addr_q <= sram_addr + 1'b1;
            sram_sel_q  <= sram_sel;
            sram_we_q   <= sram_we;
        end
    end

    // Latch next state
    always_ff @(posedge i_wb_clk, posedge i_wb_rst) begin
        if (i_wb_rst) begin
            state_q <= IDLE;
        end else begin
            state_q <= state;
        end
    end

    // Update state
    always_comb begin
        case (state_q)
            IDLE:    state = wb_slave_fifo_empty && ~i_wb_cyc ? IDLE : ACK0;
            ACK0:    state = wb_slave_fifo_empty && ~i_wb_cyc ? IDLE : (unaligned ? ACK1 : ACK0);
            ACK1:    state = wb_slave_fifo_empty && ~i_wb_cyc ? IDLE : ACK0;
            default: state = IDLE;
        endcase
    end

    // Output signals depending on state
    always_comb begin
        case (state_q)
            IDLE: begin
                o_wb_data   = 'b0;
                o_wb_ack    = 1'b0;
                o_sram_addr = 'b0;
                o_sram_we_n = 1'b1;
                o_sram_ub_n = 1'b0;
                o_sram_lb_n = 1'b0;

            end
            ACK0: begin
                o_wb_data   = sram_we ? {{(`SRAM_DATA_WIDTH){1'b0}}} : io_sram_dq;
                o_wb_ack    = ~unaligned;
                o_sram_addr = sram_addr[`SRAM_ADDR_WIDTH:1];
                o_sram_we_n = ~sram_we;
                o_sram_ub_n = unaligned ? ~sram_sel[0] : ~sram_sel[1];
                o_sram_lb_n = unaligned ? 1'b1 : ~sram_sel[0];
            end
            ACK1: begin
                o_wb_data   = sram_we_q ? {{(`SRAM_DATA_WIDTH){1'b0}}} : {io_sram_dq[7:0], sram_data_q};
                o_wb_ack    = 1'b1;
                o_sram_addr = sram_addr_q[`SRAM_ADDR_WIDTH:1];
                o_sram_we_n = ~sram_we_q;
                o_sram_ub_n = 'b1;
                o_sram_lb_n = ~sram_sel_q[1];
            end
            default: begin
                o_wb_data   = 'b0;
                o_wb_ack    = 1'b0;
                o_sram_addr = 'b0;
                o_sram_we_n = 1'b1;
                o_sram_ub_n = 1'b0;
                o_sram_lb_n = 1'b0;
            end
        endcase
    end

    sync_fifo #(
        .DATA_WIDTH(FIFO_DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) wb_slave_fifo (
        .clk(i_wb_clk),
        .n_rst(n_rst),
        .i_flush(wb_slave_fifo_flush),
        .i_fifo_rd_en(wb_slave_fifo_rd_en),
        .o_fifo_data(wb_slave_fifo_rd_data),
        .o_fifo_empty(wb_slave_fifo_empty),
        .i_fifo_wr_en(wb_slave_fifo_wr_en),
        .i_fifo_data(wb_slave_fifo_wr_data),
        .o_fifo_full(wb_slave_fifo_full)
    );

endmodule
