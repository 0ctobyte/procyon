// Integer Execution Unit
// Encapsulates the ID and EX stages
// Writes the result of the EX stage to a FIFO
// And, whenever the FIFO is not empty and is granted access to the CDB, 
// broadcasts the results of the integer op on the CDB

import types::*;

module ieu #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter TAG_WIDTH      = 6,
    parameter IEU_FIFO_DEPTH = 8
) (
    input  logic      clk,
    input  logic      n_rst,

    input  logic      i_flush,

    cdb_if.source     cdb,

    rs_funit_if.sink  rs_funit,

    arbiter_if.source arb
);

    // FIFO interfaces
    fifo_wr_if #(
        .DATA_WIDTH(DATA_WIDTH+ADDR_WIDTH+TAG_WIDTH+1)
    ) fifo_wr ();

    fifo_rd_if #(
        .DATA_WIDTH(DATA_WIDTH+ADDR_WIDTH+TAG_WIDTH+1)
    ) fifo_rd ();

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
    ieu_ex_t ieu_ex;

    // Connect FIFO write interface
    assign fifo_wr.wr_en   = ieu_ex.valid;
    assign fifo_wr.data_in = {ieu_ex.data, ieu_ex.addr, ieu_ex.tag, ieu_ex.redirect};
    assign rs_funit.stall  = fifo_wr.full;

    // Connect Arbiter interface
    assign arb.req       = ~fifo_rd.empty;
    assign fifo_rd.rd_en = arb.gnt;

    // CDB outputs
    assign cdb.en       = arb.gnt ? 'b1 : 'bz;
    assign cdb.redirect = arb.gnt ? fifo_rd.data_out[0] : 'bz;
    assign cdb.tag      = arb.gnt ? fifo_rd.data_out[TAG_WIDTH:1] : 'bz;
    assign cdb.addr     = arb.gnt ? fifo_rd.data_out[ADDR_WIDTH+TAG_WIDTH:TAG_WIDTH+1] : 'bz;
    assign cdb.data     = arb.gnt ? fifo_rd.data_out[DATA_WIDTH+ADDR_WIDTH+TAG_WIDTH:ADDR_WIDTH+TAG_WIDTH+1] : 'bz;

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
        ieu_id_q.valid    <= ieu_id.valid;
    end

    ieu_id #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TAG_WIDTH(TAG_WIDTH)
    ) ieu_id_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_opcode(rs_funit.opcode),
        .i_iaddr(rs_funit.iaddr),
        .i_insn(rs_funit.insn),
        .i_src_a(rs_funit.src_a),
        .i_src_b(rs_funit.src_b),
        .i_tag(rs_funit.tag),
        .i_valid(rs_funit.valid),
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

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH+ADDR_WIDTH+TAG_WIDTH+1),
        .FIFO_DEPTH(IEU_FIFO_DEPTH)
    ) ieu_ex_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .if_fifo_wr(fifo_wr),
        .if_fifo_rd(fifo_rd)
    );

endmodule
