module wb_master_driver #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_WB_DATA_WIDTH = 16,
    parameter OPTN_ADDR_WIDTH    = 32,

    parameter WB_DATA_SIZE       = OPTN_WB_DATA_WIDTH / 8
) (
    // Wishbone interface
    input  logic                          i_wb_clk,
    input  logic                          i_wb_rst,
    output logic                          o_wb_cyc,
    output logic                          o_wb_stb,
    output logic                          o_wb_we,
    output logic [WB_DATA_SIZE-1:0]       o_wb_sel,
    output logic [OPTN_ADDR_WIDTH-1:0]    o_wb_addr,
    output logic [OPTN_WB_DATA_WIDTH-1:0] o_wb_data,
    input  logic [OPTN_WB_DATA_WIDTH-1:0] i_wb_data,
    input  logic                          i_wb_ack,
    input  logic                          i_wb_stall,

    // Test interface
    input  logic                          i_drv_en,
    input  logic                          i_drv_we,
    input  logic [OPTN_ADDR_WIDTH-1:0]    i_drv_addr,
    input  logic [OPTN_DATA_WIDTH-1:0]    i_drv_data,
    output logic [OPTN_DATA_WIDTH-1:0]    o_drv_data,
    output logic                          o_drv_done,
    output logic                          o_drv_busy
);

    localparam DATA_SIZE         = OPTN_DATA_WIDTH / 8;
    localparam NUM_REQS          = OPTN_DATA_WIDTH / OPTN_WB_DATA_WIDTH;
    localparam NUM_ACKS          = NUM_REQS;
    localparam NUM_REQS_WIDTH    = $clog2(NUM_REQS);
    localparam NUM_ACKS_WIDTH    = $clog2(NUM_ACKS);
    localparam WB_MD_STATE_WIDTH = 2;
    localparam WB_MD_STATE_IDLE  = 2'b00;
    localparam WB_MD_STATE_REQS  = 2'b01;
    localparam WB_MD_STATE_ACKS  = 2'b10;

    logic [WB_MD_STATE_WIDTH-1:0] state;
    logic [WB_MD_STATE_WIDTH-1:0] state_q;

    logic [NUM_REQS_WIDTH:0]      req_count;
    logic [NUM_ACKS_WIDTH:0]      ack_count;

    logic                         drv_we_q;
    logic [OPTN_ADDR_WIDTH-1:0]   drv_addr_q;
    logic [OPTN_DATA_WIDTH-1:0]   drv_data_i_q;
    logic [OPTN_DATA_WIDTH-1:0]   drv_data_o_q;

    assign o_drv_data = drv_data_o_q;
    assign o_drv_done = (state_q == WB_MD_STATE_ACKS) && (ack_count == NUM_ACKS);
    assign o_drv_busy = (state_q != WB_MD_STATE_IDLE);

    // Assign static outputs
    assign o_wb_addr  = drv_addr_q;
    assign o_wb_data = drv_data_i_q[OPTN_WB_DATA_WIDTH-1:0];
    assign o_wb_we   = drv_we_q;

    always_comb begin
        case (state_q)
            WB_MD_STATE_IDLE: begin
                o_wb_cyc  = 1'b0;
                o_wb_stb  = 1'b0;
                o_wb_sel  = {(WB_DATA_SIZE){1'b1}};
            end
            WB_MD_STATE_REQS: begin
                o_wb_cyc  = 1'b1;
                o_wb_stb  = 1'b1;
                o_wb_sel  = {(WB_DATA_SIZE){1'b1}};
            end
            WB_MD_STATE_ACKS: begin
                o_wb_cyc  = 1'b1;
                o_wb_stb  = 1'b0;
                o_wb_sel  = {(WB_DATA_SIZE){1'b1}};
            end
        endcase
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            drv_data_o_q <= {(OPTN_DATA_WIDTH){1'b0}};;
        end else if (i_wb_ack) begin
            drv_data_o_q <= {i_wb_data, drv_data_o_q[OPTN_DATA_WIDTH-1:OPTN_WB_DATA_WIDTH]};
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (state_q == WB_MD_STATE_IDLE) begin
            drv_we_q <= i_drv_we;
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (state_q == WB_MD_STATE_IDLE) begin
            drv_addr_q   <= i_drv_addr;
            drv_data_i_q <= i_drv_data;
        end else if (state == WB_MD_STATE_REQS) begin
            drv_addr_q   <= drv_addr_q + WB_DATA_SIZE;
            drv_data_i_q <= {{(OPTN_WB_DATA_WIDTH){1'b0}}, drv_data_i_q[OPTN_DATA_WIDTH-1:OPTN_WB_DATA_WIDTH]};
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            req_count <= {(NUM_REQS_WIDTH+1){1'b0}};
        end else if (state_q == WB_MD_STATE_REQS) begin
            req_count <= req_count + 1'b1;
        end else begin
            req_count <= {(NUM_REQS_WIDTH+1){1'b0}};
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            ack_count <= {(NUM_ACKS_WIDTH+1){1'b0}};
        end else if (state_q == WB_MD_STATE_IDLE) begin
            ack_count <= {(NUM_ACKS_WIDTH+1){1'b0}};
        end else if (i_wb_ack) begin
            ack_count <= ack_count + 1'b1;
        end
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            state_q <= WB_MD_STATE_IDLE;
        end else begin
            state_q <= state;
        end
    end

    always_comb begin
        case (state_q)
            WB_MD_STATE_IDLE: state = i_drv_en ? WB_MD_STATE_REQS : WB_MD_STATE_IDLE;
            WB_MD_STATE_REQS: state = (req_count == (NUM_REQS-1)) ? WB_MD_STATE_ACKS : WB_MD_STATE_REQS;
            WB_MD_STATE_ACKS: state = (ack_count == NUM_ACKS) ? WB_MD_STATE_IDLE : WB_MD_STATE_ACKS;
            default:          state = WB_MD_STATE_IDLE;
        endcase
    end

endmodule
