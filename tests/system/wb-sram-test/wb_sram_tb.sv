`timescale 1ns/1ns

`include "../../common/test_common.svh"

module wb_sram_tb;

    logic                        clk;
    logic                        n_rst;
    logic                        wb_rst;

    logic [`SRAM_ADDR_WIDTH-1:0] sram_addr;
    wire  [`SRAM_DATA_WIDTH-1:0] sram_dq;
    logic                        sram_ce_n;
    logic                        sram_we_n;
    logic                        sram_oe_n;
    logic                        sram_ub_n;
    logic                        sram_lb_n;

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

    logic [`DATA_WIDTH-1:0]      cycles;
    logic [`WB_ADDR_WIDTH-1:0]   addr;
    logic [`DATA_WIDTH-1:0]      data;

    assign wb_rst = ~n_rst;

    assign drv_en     = 1'b1;
    assign drv_we     = ~cycles[0];
    assign drv_addr   = addr;
    assign drv_data_i = data;

    initial clk = 1'b1;
    always #10 clk = ~clk;

    initial begin
        n_rst = 1'b0;
        #20 n_rst = 1'b1;
    end

    always @(posedge clk) begin
        if (cycles == 32'h20) begin
            $display("----- PASS ----\n");
            $stop;
        end else if (drv_done && cycles[0] == 1'b1) begin
            if (drv_data_o == data) begin
                $display("----- OKAY -----\n");
            end else begin
                $display("----- FAIL -----\n");
                $stop;
            end
        end
    end

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            cycles <= 'b0;
        end else if (drv_done) begin
            cycles <= cycles + 1'b1;
        end
    end

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            addr <= 'b0;
            data <= 'b0;
        end else if (drv_done && cycles[0] == 1'b1) begin
            addr <= addr + 1;
            data <= data + 1;
        end
    end

    wb_sram #(
        .DATA_WIDTH(`WB_DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH),
        .BASE_ADDR(`WB_SRAM_BASE_ADDR),
        .FIFO_DEPTH(`WB_SRAM_FIFO_DEPTH)
    ) wb_sram_inst (
        .i_wb_clk(clk),
        .i_wb_rst(wb_rst),
        .i_wb_cyc(wb_cyc),
        .i_wb_stb(wb_stb),
        .i_wb_we(wb_we),
        .i_wb_sel(wb_sel),
        .i_wb_addr(wb_addr),
        .i_wb_data(wb_data_o),
        .o_wb_data(wb_data_i),
        .o_wb_ack(wb_ack),
        .o_wb_stall(wb_stall),
        .io_sram_dq(sram_dq),
        .o_sram_addr(sram_addr),
        .o_sram_ce_n(sram_ce_n),
        .o_sram_oe_n(sram_oe_n),
        .o_sram_we_n(sram_we_n),
        .o_sram_ub_n(sram_ub_n),
        .o_sram_lb_n(sram_lb_n)
    );

    wb_master_driver #(
        .DATA_WIDTH(`DATA_WIDTH),
        .WB_DATA_WIDTH(`WB_DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH)
    ) wb_master_driver_inst (
        .i_wb_clk(clk),
        .i_wb_rst(wb_rst),
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

    sram_model sram_model_inst (
        .clk(clk),
        .i_sram_addr(sram_addr),
        .io_sram_dq(sram_dq),
        .i_sram_ce_n(sram_ce_n),
        .i_sram_we_n(sram_we_n),
        .i_sram_oe_n(sram_oe_n),
        .i_sram_ub_n(sram_ub_n),
        .i_sram_lb_n(sram_lb_n)
    );

endmodule
