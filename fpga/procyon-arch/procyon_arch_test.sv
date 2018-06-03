`include "../../rtl/core/common.svh"

import procyon_types::*;

module procyon_arch_test #(
    parameter HEX_FILE = ""
) (
    input  logic         CLOCK_50,
    input  logic [17:17] SW,

    input  logic [0:0]   KEY,

    output logic [17:0]  LEDR,
    output logic [7:0]   LEDG,

    output logic [6:0]   HEX0,
    output logic [6:0]   HEX1,
    output logic [6:0]   HEX2,
    output logic [6:0]   HEX3,
    output logic [6:0]   HEX4,
    output logic [6:0]   HEX5,
    output logic [6:0]   HEX6,
    output logic [6:0]   HEX7
);
    typedef enum logic {
        RUN  = 1'b0,
        HALT = 1'b1
    } state_t;

    state_t                state;

    logic                  clk;
    logic                  n_rst;

    // FIXME: To test if simulations pass/fail
    procyon_data_t         sim_tp;

    // FIXME: FPGA debugging output
    logic                  rob_redirect;
    procyon_addr_t         rob_redirect_addr;
    logic                  regmap_retire_wr_en;
    procyon_reg_t          regmap_retire_rdest;
    procyon_data_t         regmap_retire_data;

    // FIXME: Temporary instruction cache interface
    procyon_data_t         ic_insn;
    logic                  ic_valid;
    procyon_addr_t         ic_pc;
    logic                  ic_en;

    // FIXME: Temporary data cache interface
    logic                  dc_hit;
    procyon_data_t         dc_data;
    logic                  dc_re;
    procyon_addr_t         dc_addr;

    // FIXME: Temporary store retire to cache interface
    logic                  sq_retire_dc_hit;
    logic                  sq_retire_msq_full;
    logic                  sq_retire_en;
    procyon_byte_select_t  sq_retire_byte_en;
    procyon_addr_t         sq_retire_addr;
    procyon_data_t         sq_retire_data;

    logic           key0;
    logic           key_pulse;
    logic [6:0]     o_hex [0:7];

    assign n_rst            = SW[17];

    assign key0             = ~KEY[0];
    assign LEDR[17]         = SW[17];
    assign LEDR[16]         = rob_redirect;
    assign LEDR[15:0]       = rob_redirect_addr[15:0];
    assign LEDG             = regmap_retire_rdest;
    assign HEX0             = o_hex[0];
    assign HEX1             = o_hex[1];
    assign HEX2             = o_hex[2];
    assign HEX3             = o_hex[3];
    assign HEX4             = o_hex[4];
    assign HEX5             = o_hex[5];
    assign HEX6             = o_hex[6];
    assign HEX7             = o_hex[7];

    always_comb begin
        case (state)
            RUN:  clk = CLOCK_50;
            HALT: clk = 1'b0;
        endcase
    end

    always_ff @(negedge CLOCK_50, negedge n_rst) begin
        if (~n_rst) begin
            state <= RUN;
        end else begin
            case (state)
                RUN:  state <= regmap_retire_wr_en ? HALT : RUN;
                HALT: state <= key_pulse ? RUN : HALT;
            endcase
        end
    end

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : SEG7_DECODER_INSTANCES
            seg7_decoder seg7_decoder_inst (
                .n_rst(n_rst),
                .i_hex(regmap_retire_data[i*4+3:i*4]),
                .o_hex(o_hex[i])
            );
        end
    endgenerate

    edge_detector edge_detector_inst (
        .clk(CLOCK_50),
        .n_rst(n_rst),
        .i_async(key0),
        .o_pulse(key_pulse)
    );

    boot_rom #(
        .HEX_FILE(HEX_FILE)
    ) boot_rom_inst (
        .o_ic_insn(ic_insn),
        .o_ic_valid(ic_valid),
        .i_ic_pc(ic_pc),
        .i_ic_en(ic_en)
    );

    data_ram #(
        .HEX_FILE(HEX_FILE)
    ) data_ram_inst (
        .clk(clk),
        .o_dc_hit(dc_hit),
        .o_dc_data(dc_data),
        .i_dc_re(dc_re),
        .i_dc_addr(dc_addr),
        .o_sq_retire_dc_hit(sq_retire_dc_hit),
        .o_sq_retire_msq_full(sq_retire_msq_full),
        .i_sq_retire_en(sq_retire_en),
        .i_sq_retire_byte_en(sq_retire_byte_en),
        .i_sq_retire_addr(sq_retire_addr),
        .i_sq_retire_data(sq_retire_data)
    );

    procyon procyon (
        .clk(clk),
        .n_rst(n_rst),
        .o_sim_tp(sim_tp),
        .o_rob_redirect(rob_redirect),
        .o_rob_redirect_addr(rob_redirect_addr),
        .o_regmap_retire_wr_en(regmap_retire_wr_en),
        .o_regmap_retire_rdest(regmap_retire_rdest),
        .o_regmap_retire_data(regmap_retire_data),
        .i_ic_insn(ic_insn),
        .i_ic_valid(ic_valid),
        .o_ic_pc(ic_pc),
        .o_ic_en(ic_en),
        .i_dc_hit(dc_hit),
        .i_dc_data(dc_data),
        .o_dc_re(dc_re),
        .o_dc_addr(dc_addr),
        .i_sq_retire_dc_hit(sq_retire_dc_hit),
        .i_sq_retire_msq_full(sq_retire_msq_full),
        .o_sq_retire_en(sq_retire_en),
        .o_sq_retire_byte_en(sq_retire_byte_en),
        .o_sq_retire_addr(sq_retire_addr),
        .o_sq_retire_data(sq_retire_data)
    );

endmodule
