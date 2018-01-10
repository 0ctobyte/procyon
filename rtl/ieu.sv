// Integer Execution Unit
// Encapsulates the ID and EX stages
// Writes the result of the EX stage to the CDB when it is available

`include "common.svh"
import types::*;

module ieu #(
    parameter DATA_WIDTH     = `DATA_WIDTH,
    parameter ADDR_WIDTH     = `ADDR_WIDTH,
    parameter TAG_WIDTH      = `TAG_WIDTH
) (
    input  logic                     clk,
    input  logic                     n_rst,

    input  logic                     i_flush,

    // Common Data Bus
    output logic [DATA_WIDTH-1:0]    o_cdb_data,
    output logic [ADDR_WIDTH-1:0]    o_cdb_addr,
    output logic [TAG_WIDTH-1:0]     o_cdb_tag,
    output logic                     o_cdb_redirect,
    output logic                     o_cdb_en,

    input  logic                     i_fu_valid,
    input  opcode_t                  i_fu_opcode,
    input  logic [ADDR_WIDTH-1:0]    i_fu_iaddr,
    input  logic [DATA_WIDTH-1:0]    i_fu_insn,
    input  logic [DATA_WIDTH-1:0]    i_fu_src_a,
    input  logic [DATA_WIDTH-1:0]    i_fu_src_b,
    input  logic [TAG_WIDTH-1:0]     i_fu_tag,
    output logic                     o_fu_stall
);

    typedef struct packed {
        alu_func_t             alu_func;
        logic [DATA_WIDTH-1:0] src_a;
        logic [DATA_WIDTH-1:0] src_b;
        logic [ADDR_WIDTH-1:0] iaddr;
        logic [DATA_WIDTH-1:0] imm_b;
        logic [4:0]            shamt;
        logic [TAG_WIDTH-1:0]  tag;
        logic                  jmp;
        logic                  br;
        logic                  valid;
    } ieu_id_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0] data;
        logic [ADDR_WIDTH-1:0] addr;
        logic [TAG_WIDTH-1:0]  tag;
        logic                  redirect;
        logic                  valid;
    } ieu_ex_t;

    ieu_id_t ieu_id, ieu_id_q;
    ieu_ex_t ieu_ex, ieu_ex_q;

    assign o_fu_stall      = 1'b0;

    // CDB outputs
    assign o_cdb_en        = ieu_ex_q.valid;
    assign o_cdb_redirect  = ieu_ex_q.redirect;
    assign o_cdb_tag       = ieu_ex_q.tag;
    assign o_cdb_addr      = ieu_ex_q.addr;
    assign o_cdb_data      = ieu_ex_q.data;

    // Make sure valid bit is set to false on flush or reset
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            ieu_id_q.valid <= 'b0;
        end else if (i_flush) begin
            ieu_id_q.valid <= 'b0;
        end else begin
            ieu_id_q.valid <= ieu_id.valid;
        end
    end 

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            ieu_ex_q.valid <= 'b0;
        end else if (i_flush) begin
            ieu_ex_q.valid <= 'b0;
        end else begin
            ieu_ex_q.valid <= ieu_ex.valid;
        end
    end 

    // ID -> EX pipelined registers
    always_ff @(posedge clk) begin
        ieu_id_q.alu_func <= ieu_id.alu_func;
        ieu_id_q.src_a    <= ieu_id.src_a;
        ieu_id_q.src_b    <= ieu_id.src_b;
        ieu_id_q.iaddr    <= ieu_id.iaddr;
        ieu_id_q.imm_b    <= ieu_id.imm_b;
        ieu_id_q.shamt    <= ieu_id.shamt;
        ieu_id_q.tag      <= ieu_id.tag;
        ieu_id_q.jmp      <= ieu_id.jmp;
        ieu_id_q.br       <= ieu_id.br;
    end

    // EX -> WB pipelined registers
    always_ff @(posedge clk) begin
        ieu_ex_q.redirect <= ieu_ex.redirect;
        ieu_ex_q.tag      <= ieu_ex.tag;
        ieu_ex_q.addr     <= ieu_ex.addr;
        ieu_ex_q.data     <= ieu_ex.data;
    end

    ieu_id #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TAG_WIDTH(TAG_WIDTH)
    ) ieu_id_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_opcode(i_fu_opcode),
        .i_iaddr(i_fu_iaddr),
        .i_insn(i_fu_insn),
        .i_src_a(i_fu_src_a),
        .i_src_b(i_fu_src_b),
        .i_tag(i_fu_tag),
        .i_valid(i_fu_valid),
        .o_alu_func(ieu_id.alu_func),
        .o_src_a(ieu_id.src_a),
        .o_src_b(ieu_id.src_b),
        .o_iaddr(ieu_id.iaddr),
        .o_imm_b(ieu_id.imm_b),
        .o_shamt(ieu_id.shamt),
        .o_tag(ieu_id.tag),
        .o_jmp(ieu_id.jmp),
        .o_br(ieu_id.br),
        .o_valid(ieu_id.valid)
    );

    ieu_ex #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TAG_WIDTH(TAG_WIDTH)
    ) ieu_ex_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_alu_func(ieu_id_q.alu_func),
        .i_src_a(ieu_id_q.src_a),
        .i_src_b(ieu_id_q.src_b),
        .i_iaddr(ieu_id_q.iaddr),
        .i_imm_b(ieu_id_q.imm_b),
        .i_shamt(ieu_id_q.shamt),
        .i_tag(ieu_id_q.tag),
        .i_jmp(ieu_id_q.jmp),
        .i_br(ieu_id_q.br),
        .i_valid(ieu_id_q.valid),
        .o_data(ieu_ex.data),
        .o_addr(ieu_ex.addr),
        .o_tag(ieu_ex.tag),
        .o_redirect(ieu_ex.redirect),
        .o_valid(ieu_ex.valid)
    );

endmodule
