`include "test_common.svh"

module wb_master_driver #(
    parameter  DATA_WIDTH    = `DATA_WIDTH,
    parameter  WB_DATA_WIDTH = `WB_DATA_WIDTH,
    parameter  ADDR_WIDTH    = `WB_ADDR_WIDTH
) (
    // Wishbone interface
    input  logic                       i_wb_clk,
    input  logic                       i_wb_rst,
    output logic                       o_wb_cyc,
    output logic                       o_wb_stb,
    output logic                       o_wb_we,
    output logic [WB_DATA_WIDTH/8-1:0] o_wb_sel,
    output logic [ADDR_WIDTH-1:0]      o_wb_addr,
    output logic [`WB_DATA_WIDTH-1:0]  o_wb_data,
    input  logic [`WB_DATA_WIDTH-1:0]  i_wb_data,
    input  logic                       i_wb_ack,
    input  logic                       i_wb_stall,

    // Test interface
    input  logic                       i_drv_en,
    input  logic                       i_drv_we,
    input  logic [ADDR_WIDTH-1:0]      i_drv_addr,
    input  logic [DATA_WIDTH-1:0]      i_drv_data,
    output logic [DATA_WIDTH-1:0]      o_drv_data,
    output logic                       o_drv_done,
    output logic                       o_drv_busy
);

    localparam WORD_SIZE     = DATA_WIDTH/8;
    localparam WB_WORD_SIZE  = WB_DATA_WIDTH/8;
    localparam NUM_REQS      = DATA_WIDTH/WB_DATA_WIDTH;
    localparam NUM_ACKS      = NUM_REQS;

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        REQS = 2'b01,
        ACKS = 2'b10
    } state_t;

    state_t                    state;
    state_t                    state_q;

    logic [$clog2(NUM_REQS):0] req_count;
    logic [$clog2(NUM_ACKS):0] ack_count;

    logic                      drv_we_q;
    logic [ADDR_WIDTH-1:0]     drv_addr_q;
    logic [DATA_WIDTH-1:0]     drv_data_i_q;
    logic [DATA_WIDTH-1:0]     drv_data_o_q;

    assign o_drv_data  = drv_data_o_q;
    assign o_drv_done  = (state_q == ACKS) && (ack_count == NUM_ACKS);
    assign o_drv_busy  = (state_q != IDLE);

    // Assign static outputs
    assign o_wb_addr   = drv_addr_q;
    assign o_wb_data   = drv_data_i_q[`WB_DATA_WIDTH-1:0];
    assign o_wb_we     = drv_we_q;

    always_comb begin
        case (state_q)
            IDLE: begin
                o_wb_cyc  = 1'b0;
                o_wb_stb  = 1'b0;
                o_wb_sel  = 'b0;
            end
            REQS: begin
                o_wb_cyc  = 1'b1;
                o_wb_stb  = 1'b1;
                o_wb_sel  = {(WB_WORD_SIZE){1'b1}};
            end
            ACKS: begin
                o_wb_cyc  = 1'b1;
                o_wb_stb  = 1'b0;
                o_wb_sel  = 'b0;
            end
        endcase
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            drv_data_o_q <= 'b0;
        end else if (i_wb_ack) begin
            drv_data_o_q <= {i_wb_data, drv_data_o_q[DATA_WIDTH-1:WB_DATA_WIDTH]};
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (state_q == IDLE) begin
            drv_we_q <= i_drv_we;
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (state_q == IDLE) begin
            drv_addr_q   <= i_drv_addr;
            drv_data_i_q <= i_drv_data;
        end else if (state == REQS) begin
            drv_addr_q   <= drv_addr_q + WB_WORD_SIZE;
            drv_data_i_q <= {{(WB_DATA_WIDTH){1'b0}}, drv_data_i_q[DATA_WIDTH-1:WB_DATA_WIDTH]};
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            req_count <= 'b0;
        end else if (state_q == REQS) begin
            req_count <= req_count + 1'b1;
        end else begin
            req_count <= 'b0;
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            ack_count <= 'b0;
        end else if (state_q == IDLE) begin
            ack_count <= 'b0;
        end else if (i_wb_ack) begin
            ack_count <= ack_count + 1'b1;
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            state_q <= IDLE;
        end else begin
            state_q <= state;
        end
    end

    always_comb begin
        case (state_q)
            IDLE:    state = i_drv_en ? REQS : IDLE;
            REQS:    state = (req_count == (NUM_REQS-1)) ? ACKS : REQS;
            ACKS:    state = (ack_count == NUM_ACKS) ? IDLE : ACKS;
            default: state = IDLE;
        endcase
    end

endmodule
