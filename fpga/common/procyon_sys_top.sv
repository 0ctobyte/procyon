/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

`define SRAM_ADDR_WIDTH 20
`define SRAM_DATA_WIDTH 16

`define WB_CTI_WIDTH 3
`define WB_BTE_WIDTH 2

module procyon_sys_top #(
    parameter OPTN_DATA_WIDTH         = 32,
    parameter OPTN_INSN_WIDTH         = 32,
    parameter OPTN_ADDR_WIDTH         = 32,
    parameter OPTN_RAT_DEPTH          = 32,
    parameter OPTN_NUM_IEU            = 1,
    parameter OPTN_INSN_FIFO_DEPTH    = 8,
    parameter OPTN_ROB_DEPTH          = 12,
    parameter OPTN_RS_IEU_DEPTH       = 7,
    parameter OPTN_RS_LSU_DEPTH       = 5,
    parameter OPTN_LQ_DEPTH           = 5,
    parameter OPTN_SQ_DEPTH           = 4,
    parameter OPTN_VQ_DEPTH           = 1,
    parameter OPTN_MHQ_DEPTH          = 2,
    parameter OPTN_IFQ_DEPTH          = 1,
    parameter OPTN_IC_CACHE_SIZE      = 1024,
    parameter OPTN_IC_LINE_SIZE       = 32,
    parameter OPTN_IC_WAY_COUNT       = 1,
    parameter OPTN_DC_CACHE_SIZE      = 1024,
    parameter OPTN_DC_LINE_SIZE       = 32,
    parameter OPTN_DC_WAY_COUNT       = 1,
    parameter OPTN_WB_DATA_WIDTH      = 32,
    parameter OPTN_WB_ADDR_WIDTH      = 32,
    parameter OPTN_WB_SRAM_BASE_ADDR  = 0,
    parameter OPTN_HEX_FILE           = "",
    parameter OPTN_HEX_SIZE           = 0
)(
    input       logic                        CLOCK_50,
    input       logic [17:17]                SW,

    input       logic [1:0]                  KEY,

    output      logic [17:0]                 LEDR,
    output      logic [4:0]                  LEDG,

    inout  wire logic [`SRAM_DATA_WIDTH-1:0] SRAM_DQ,
    output      logic [`SRAM_ADDR_WIDTH-1:0] SRAM_ADDR,
    output      logic                        SRAM_CE_N,
    output      logic                        SRAM_WE_N,
    output      logic                        SRAM_OE_N,
    output      logic                        SRAM_LB_N,
    output      logic                        SRAM_UB_N,

    output      logic [6:0]                  HEX0,
    output      logic [6:0]                  HEX1,
    output      logic [6:0]                  HEX2,
    output      logic [6:0]                  HEX3,
    output      logic [6:0]                  HEX4,
    output      logic [6:0]                  HEX5,
    output      logic [6:0]                  HEX6,
    output      logic [6:0]                  HEX7
);

    localparam IC_LINE_WIDTH    = OPTN_IC_LINE_SIZE * 8;
    localparam RAT_IDX_WIDTH    = $clog2(OPTN_RAT_DEPTH);
    localparam WB_DATA_SIZE     = OPTN_WB_DATA_WIDTH / 8;
    localparam ROM_ADDR_WIDTH   = OPTN_HEX_SIZE == 1 ? 1 : $clog2(OPTN_HEX_SIZE);
    localparam TEST_STATE_WIDTH = 2;

    typedef enum logic [TEST_STATE_WIDTH-1:0] {
        TEST_STATE_RUN   = 2'b00,
        TEST_STATE_STEP  = 2'b01,
        TEST_STATE_HALT  = 2'b10,
        TEST_STATE_DONE  = 2'b11
    } test_state_t;

    logic rst_sync;
    procyon_sync #(.OPTN_DATA_WIDTH(1), .OPTN_SYNC_DEPTH(2)) rst_sync_sync (.clk(CLOCK_50), .n_rst(1'b1), .i_async_data(SW[17]), .o_sync_data(rst_sync));

    logic n_rst;
    logic [1:0] key;
    logic [1:0] key_pulse;

    assign key = ~KEY;

    genvar inst;
    generate
    for (inst = 0; inst < 2; inst++) begin : GEN_EDGE_DETECTOR_INST
        procyon_edge_detector procyon_edge_detector_inst (
            .clk(CLOCK_50),
            .n_rst(n_rst),
            .i_async(key[inst]),
            .o_pulse(key_pulse[inst])
        );
    end
    endgenerate

    assign LEDR[17] = rst_sync;
    assign n_rst = rst_sync;
    assign wb_rst = ~n_rst;

    // FIXME: To test if simulations pass/fail
    logic [OPTN_DATA_WIDTH-1:0] sim_tp;

    // FIXME: FPGA debugging output
    logic rob_redirect;
    logic [OPTN_ADDR_WIDTH-1:0] rob_redirect_addr;
    logic rat_retire_en;
    logic [RAT_IDX_WIDTH-1:0] rat_retire_rdst;
    logic [OPTN_DATA_WIDTH-1:0] rat_retire_data;

    logic clk;
    logic rob_redirect_r;
/* verilator lint_off UNUSED */
    logic [OPTN_ADDR_WIDTH-1:0] rob_redirect_addr_r;
/* verilator lint_on  UNUSED */
    logic [RAT_IDX_WIDTH-1:0] rat_retire_rdst_r;
    logic [OPTN_DATA_WIDTH-1:0] rat_retire_data_next;
    logic [OPTN_DATA_WIDTH-1:0] rat_retire_data_r;

    logic test_finished;
    logic test_state_done;

    assign test_finished = (sim_tp == 'h4a33) | (sim_tp == 'hfae1);
    assign test_state_done = (test_state_r == TEST_STATE_DONE);

    test_state_t test_state_next;
    test_state_t test_state_r;

    always_comb begin
        unique case (test_state_r)
            TEST_STATE_RUN:  test_state_next = test_finished ? TEST_STATE_DONE : (key_pulse[1] ? TEST_STATE_STEP : TEST_STATE_RUN);
            TEST_STATE_STEP: test_state_next = rat_retire_en ? TEST_STATE_HALT : TEST_STATE_STEP;
            TEST_STATE_HALT: test_state_next = key_pulse[1] ? TEST_STATE_RUN : (key_pulse[0] ? TEST_STATE_STEP : TEST_STATE_HALT);
            TEST_STATE_DONE: test_state_next = key_pulse[1] ? TEST_STATE_RUN : (key_pulse[0] ? TEST_STATE_STEP : TEST_STATE_DONE);
        endcase
    end

    procyon_srff #(TEST_STATE_WIDTH) test_state_r_srff (.clk(CLOCK_50), .n_rst(n_rst), .i_en(1'b1), .i_set(test_state_next), .i_reset(TEST_STATE_STEP), .o_q(test_state_r));

    always_comb begin
        rat_retire_data_next = test_state_done ? sim_tp : rat_retire_data;
        clk = CLOCK_50 | test_state_r[1];
    end

    logic enable;
    assign enable = rat_retire_en & (test_state_r == TEST_STATE_STEP);

    procyon_ff #(1) rob_redirect_r_ff (.clk(CLOCK_50), .i_en(enable), .i_d(rob_redirect), .o_q(rob_redirect_r));
    procyon_ff #(OPTN_ADDR_WIDTH) rob_redirect_addr_r_ff (.clk(CLOCK_50), .i_en(enable), .i_d(rob_redirect_addr), .o_q(rob_redirect_addr_r));
    procyon_ff #(RAT_IDX_WIDTH) rat_retire_rdst_r_ff (.clk(CLOCK_50), .i_en(enable), .i_d(rat_retire_rdst), .o_q(rat_retire_rdst_r));

    logic data_enable;
    assign data_enable = enable | test_state_done;

    procyon_ff #(OPTN_DATA_WIDTH) rat_retire_data_r_ff (.clk(CLOCK_50), .i_en(data_enable), .i_d(rat_retire_data_next), .o_q(rat_retire_data_r));

    assign LEDR[16] = rob_redirect_r;
    assign LEDR[15:0] = rob_redirect_addr_r[15:0];
    assign LEDG = rat_retire_rdst_r;

    logic [6:0] o_hex [0:7];

    generate
        for (inst = 0; inst < 8; inst++) begin : GEN_SEG7_DECODER_INSTANCES
            procyon_seg7_decoder procyon_seg7_decoder_inst (
                .n_rst(n_rst),
                .i_hex(rat_retire_data_r[inst*4 +: 4]),
                .o_hex(o_hex[inst])
            );
        end
    endgenerate

    assign HEX0 = o_hex[0];
    assign HEX1 = o_hex[1];
    assign HEX2 = o_hex[2];
    assign HEX3 = o_hex[3];
    assign HEX4 = o_hex[4];
    assign HEX5 = o_hex[5];
    assign HEX6 = o_hex[6];
    assign HEX7 = o_hex[7];

    // Wishbone interface
    logic wb_rst;
    logic wb_ack;
    logic [OPTN_WB_DATA_WIDTH-1:0] wb_data_i;
    logic wb_cyc;
    logic wb_stb;
    logic wb_we;
    logic [`WB_CTI_WIDTH-1:0] wb_cti;
    logic [`WB_BTE_WIDTH-1:0] wb_bte;
    logic [WB_DATA_SIZE-1:0] wb_sel;
    logic [OPTN_WB_ADDR_WIDTH-1:0] wb_addr;
    logic [OPTN_WB_DATA_WIDTH-1:0] wb_data_o;
    logic boot_wb_cyc;
    logic boot_wb_stb;
    logic boot_wb_we;
    logic [`WB_CTI_WIDTH-1:0] boot_wb_cti;
    logic [`WB_BTE_WIDTH-1:0] boot_wb_bte;
    logic [WB_DATA_SIZE-1:0] boot_wb_sel;
    logic [OPTN_WB_ADDR_WIDTH-1:0] boot_wb_addr;
    logic [OPTN_WB_DATA_WIDTH-1:0] boot_wb_data_o;
    logic core_wb_cyc;
    logic core_wb_stb;
    logic core_wb_we;
    logic [`WB_CTI_WIDTH-1:0] core_wb_cti;
    logic [`WB_BTE_WIDTH-1:0] core_wb_bte;
    logic [WB_DATA_SIZE-1:0] core_wb_sel;
    logic [OPTN_WB_ADDR_WIDTH-1:0] core_wb_addr;
    logic [OPTN_WB_DATA_WIDTH-1:0] core_wb_data_o;

    logic boot_ctrl_done;
    logic [IC_LINE_WIDTH-1:0] rom_data;
    logic [ROM_ADDR_WIDTH-1:0] rom_addr;

    procyon_rom #(
        .OPTN_DATA_WIDTH(IC_LINE_WIDTH),
        .OPTN_ROM_DEPTH(OPTN_HEX_SIZE),
        .OPTN_ROM_FILE(OPTN_HEX_FILE)
    ) boot_rom_inst (
        .i_rom_addr(rom_addr),
        .o_rom_data(rom_data)
    );

    boot_ctrl #(
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_HEX_SIZE(OPTN_HEX_SIZE),
        .OPTN_IC_LINE_SIZE(OPTN_IC_LINE_SIZE)
    ) boot_ctrl_inst (
        .i_wb_clk(clk),
        .i_wb_rst(wb_rst),
        .i_wb_ack(wb_ack),
        .i_wb_data(wb_data_i),
        .o_wb_cyc(boot_wb_cyc),
        .o_wb_stb(boot_wb_stb),
        .o_wb_we(boot_wb_we),
        .o_wb_cti(boot_wb_cti),
        .o_wb_bte(boot_wb_bte),
        .o_wb_sel(boot_wb_sel),
        .o_wb_addr(boot_wb_addr),
        .o_wb_data(boot_wb_data_o),
        .i_rom_data(rom_data),
        .o_rom_addr(rom_addr),
        .o_boot_ctrl_done(boot_ctrl_done)
    );

    procyon #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_INSN_WIDTH(OPTN_INSN_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_RAT_DEPTH(OPTN_RAT_DEPTH),
        .OPTN_NUM_IEU(OPTN_NUM_IEU),
        .OPTN_INSN_FIFO_DEPTH(OPTN_INSN_FIFO_DEPTH),
        .OPTN_ROB_DEPTH(OPTN_ROB_DEPTH),
        .OPTN_RS_IEU_DEPTH(OPTN_RS_IEU_DEPTH),
        .OPTN_RS_LSU_DEPTH(OPTN_RS_LSU_DEPTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_VQ_DEPTH(OPTN_VQ_DEPTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_IFQ_DEPTH(OPTN_IFQ_DEPTH),
        .OPTN_IC_CACHE_SIZE(OPTN_IC_CACHE_SIZE),
        .OPTN_IC_LINE_SIZE(OPTN_IC_LINE_SIZE),
        .OPTN_IC_WAY_COUNT(OPTN_IC_WAY_COUNT),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH)
    ) procyon_inst (
        .clk(clk),
        .n_rst(boot_ctrl_done),
        .o_sim_tp(sim_tp),
        .o_rob_redirect(rob_redirect),
        .o_rob_redirect_addr(rob_redirect_addr),
        .o_rat_retire_en(rat_retire_en),
        .o_rat_retire_rdst(rat_retire_rdst),
        .o_rat_retire_data(rat_retire_data),
        .i_wb_clk(clk),
        .i_wb_rst(wb_rst),
        .i_wb_ack(wb_ack),
        .i_wb_data(wb_data_i),
        .o_wb_cyc(core_wb_cyc),
        .o_wb_stb(core_wb_stb),
        .o_wb_we(core_wb_we),
        .o_wb_cti(core_wb_cti),
        .o_wb_bte(core_wb_bte),
        .o_wb_sel(core_wb_sel),
        .o_wb_addr(core_wb_addr),
        .o_wb_data(core_wb_data_o)
    );

    // Wishbone bus mux
    assign wb_cyc = boot_ctrl_done ? core_wb_cyc : boot_wb_cyc;
    assign wb_stb = boot_ctrl_done ? core_wb_stb : boot_wb_stb;
    assign wb_we = boot_ctrl_done ? core_wb_we : boot_wb_we;
    assign wb_cti = boot_ctrl_done ? core_wb_cti : boot_wb_cti;
    assign wb_bte = boot_ctrl_done ? core_wb_bte : boot_wb_bte;
    assign wb_sel = boot_ctrl_done ? core_wb_sel : boot_wb_sel;
    assign wb_addr = boot_ctrl_done ? core_wb_addr : boot_wb_addr;
    assign wb_data_o = boot_ctrl_done ? core_wb_data_o : boot_wb_data_o;

    sram_top #(
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_BASE_ADDR(OPTN_WB_SRAM_BASE_ADDR)
    ) sram_top_inst (
        .i_wb_clk(clk),
        .i_wb_rst(wb_rst),
        .i_wb_cyc(wb_cyc),
        .i_wb_stb(wb_stb),
        .i_wb_we(wb_we),
        .i_wb_cti(wb_cti),
        .i_wb_bte(wb_bte),
        .i_wb_sel(wb_sel),
        .i_wb_addr(wb_addr),
        .i_wb_data(wb_data_o),
        .o_wb_data(wb_data_i),
        .o_wb_ack(wb_ack),
        .o_sram_ce_n(SRAM_CE_N),
        .o_sram_oe_n(SRAM_OE_N),
        .o_sram_lb_n(SRAM_LB_N),
        .o_sram_we_n(SRAM_WE_N),
        .o_sram_ub_n(SRAM_UB_N),
        .o_sram_addr(SRAM_ADDR),
        .io_sram_dq(SRAM_DQ)
    );

endmodule
