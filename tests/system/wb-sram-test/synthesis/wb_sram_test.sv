`include "../../../common/test_common.svh"

module wb_sram_test (
    input  logic                         CLOCK_50,

    input  logic [17:0]                  SW,
    input  logic [3:0]                   KEY,
    output logic [17:0]                  LEDR,
    output logic [7:0]                   LEDG,

    inout  wire  [`SRAM_DATA_WIDTH-1:0]  SRAM_DQ,
    output logic [`SRAM_ADDR_WIDTH-1:0]  SRAM_ADDR,
    output logic                         SRAM_CE_N,
    output logic                         SRAM_WE_N,
    output logic                         SRAM_OE_N,
    output logic                         SRAM_LB_N,
    output logic                         SRAM_UB_N,

    output logic [6:0]                   HEX0,
    output logic [6:0]                   HEX1,
    output logic [6:0]                   HEX2,
    output logic [6:0]                   HEX3,
    output logic [6:0]                   HEX4,
    output logic [6:0]                   HEX5,
    output logic [6:0]                   HEX6,
    output logic [6:0]                   HEX7
);

    logic                        n_rst;

    logic                        wb_cyc;
    logic                        wb_stb;
    logic                        wb_we;
    logic [`WB_WORD_SIZE-1:0]    wb_sel;
    logic [`WB_ADDR_WIDTH-1:0]   wb_addr;
    logic [`WB_DATA_WIDTH-1:0]   wb_data_i;
    logic [`WB_DATA_WIDTH-1:0]   wb_data_o;
    logic                        wb_ack;
    logic                        wb_stall;

    logic                        drv_en;
    logic                        drv_we;
    logic [`WB_ADDR_WIDTH-1:0]   drv_addr;
    logic [`DATA_WIDTH-1:0]      drv_data_o;
    logic [`DATA_WIDTH-1:0]      drv_data_i;
    logic                        drv_done;
    logic                        drv_busy;

    logic [3:0]                  key_pulse;

    logic [`DATA_WIDTH-1:0]      out_data;

    assign n_rst = ~SW[17];
    assign LEDR[17]    = SW[17];
    assign LEDR[16]    = drv_we;
    assign LEDR[15:0]  = SW[15:0];
    assign LEDG  = drv_addr;

    assign drv_en = key_pulse && ~drv_busy;
    assign drv_data_i = SW[`SRAM_DATA_WIDTH-1:0];
    assign drv_we = key_pulse[1] ? 1'b1 : 1'b0;

    always_ff @(posedge CLOCK_50) begin
        if (drv_done && ~drv_we) begin
            out_data <= drv_data_o;
        end
    end

    always_ff @(posedge CLOCK_50, posedge SW[17]) begin
        if (SW[17]) begin
            drv_addr <= 'b0;
        end else if (key_pulse[2]) begin
            drv_addr <= drv_addr - 1;
        end else if (key_pulse[3]) begin
            drv_addr <= drv_addr + 1;
        end
    end

    wb_sram #(
        .DATA_WIDTH(`WB_DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH),
        .BASE_ADDR(`WB_SRAM_BASE_ADDR),
        .FIFO_DEPTH(`WB_SRAM_FIFO_DEPTH)
    ) wb_sram_inst (
        .i_wb_clk(CLOCK_50),
        .i_wb_rst(SW[17]),
        .i_wb_cyc(wb_cyc),
        .i_wb_stb(wb_stb),
        .i_wb_we(wb_we),
        .i_wb_sel(wb_sel),
        .i_wb_addr(wb_addr),
        .i_wb_data(wb_data_o),
        .o_wb_data(wb_data_i),
        .o_wb_ack(wb_ack),
        .o_wb_stall(wb_stall),
        .io_sram_dq(SRAM_DQ),
        .o_sram_addr(SRAM_ADDR),
        .o_sram_ce_n(SRAM_CE_N),
        .o_sram_oe_n(SRAM_OE_N),
        .o_sram_we_n(SRAM_WE_N),
        .o_sram_ub_n(SRAM_UB_N),
        .o_sram_lb_n(SRAM_LB_N)
    );

    wb_master_driver #(
        .DATA_WIDTH(`DATA_WIDTH),
        .WB_DATA_WIDTH(`WB_DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH)
    ) wb_master_driver_inst (
        .i_wb_clk(CLOCK_50),
        .i_wb_rst(SW[17]),
        .o_wb_cyc(wb_cyc),
        .o_wb_stb(wb_stb),
        .o_wb_we(wb_we),
        .o_wb_sel(wb_sel),
        .o_wb_addr(wb_addr),
        .o_wb_data(wb_data_o),
        .i_wb_data(wb_data_i),
        .i_wb_ack(wb_ack),
        .i_wb_stall(wb_stall),
        .i_drv_en(drv_en),
        .i_drv_we(drv_we),
        .i_drv_addr(drv_addr),
        .i_drv_data(drv_data_i),
        .o_drv_data(drv_data_o),
        .o_drv_done(drv_done),
        .o_drv_busy(drv_busy)
    );

    genvar i;
    generate
    for (i = 0; i < 4; i++) begin : GENERATE_EDGE_DETECTORS
        edge_detector #(
            .EDGE(1)
        ) edge_detector_inst (
            .clk(CLOCK_50),
            .n_rst(n_rst),
            .i_async(KEY[i]),
            .o_pulse(key_pulse[i])
        );
    end
    endgenerate

    seg7_decoder seg7_inst0 (
        .n_rst(n_rst),
        .i_hex(out_data[3:0]),
        .o_hex(HEX0)
    );

    seg7_decoder seg7_inst1 (
        .n_rst(n_rst),
        .i_hex(out_data[7:4]),
        .o_hex(HEX1)
    );

    seg7_decoder seg7_inst2 (
        .n_rst(n_rst),
        .i_hex(out_data[11:8]),
        .o_hex(HEX2)
    );

    seg7_decoder seg7_inst3 (
        .n_rst(n_rst),
        .i_hex(out_data[15:12]),
        .o_hex(HEX3)
    );

    seg7_decoder seg7_inst4 (
        .n_rst(n_rst),
        .i_hex(out_data[19:16]),
        .o_hex(HEX4)
    );

    seg7_decoder seg7_inst5 (
        .n_rst(n_rst),
        .i_hex(out_data[23:20]),
        .o_hex(HEX5)
    );

    seg7_decoder seg7_inst6 (
        .n_rst(n_rst),
        .i_hex(out_data[27:24]),
        .o_hex(HEX6)
    );

    seg7_decoder seg7_inst7 (
        .n_rst(n_rst),
        .i_hex(out_data[31:28]),
        .o_hex(HEX7)
    );

endmodule
