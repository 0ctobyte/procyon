// Integer Execution Unit - Execution Stage

`include "procyon_constants.svh"

module procyon_ieu_ex #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                             clk,
    input  logic                             n_rst,

    input  logic                             i_flush,

    input  logic [`PCYN_ALU_FUNC_WIDTH-1:0]  i_alu_func,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_src_a,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_src_b,
    input  logic [OPTN_ADDR_WIDTH-1:0]       i_iaddr,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_imm_b,
    input  logic [`PCYN_ALU_SHAMT_WIDTH-1:0] i_shamt,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]    i_tag,
    input  logic                             i_jmp,
    input  logic                             i_br,
    input  logic                             i_valid,

    output logic [OPTN_DATA_WIDTH-1:0]       o_data,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_addr,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]    o_tag,
    output logic                             o_redirect,
    output logic                             o_valid
);

    logic [OPTN_DATA_WIDTH-1:0]        result;

    // Extended src_a for arithmetic right shifts
    logic [OPTN_DATA_WIDTH*2-1:0]      e_src_a;

    // Signed src inputs
    logic signed [OPTN_DATA_WIDTH-1:0] s_src_a;
    logic signed [OPTN_DATA_WIDTH-1:0] s_src_b;

    assign e_src_a = {{(OPTN_DATA_WIDTH){i_src_a[OPTN_DATA_WIDTH-1]}}, i_src_a};
    assign s_src_a = i_src_a;
    assign s_src_b = i_src_b;

    // ALU
    always_comb begin
        case (i_alu_func)
            `PCYN_ALU_FUNC_ADD: result = i_src_a + i_src_b;
            `PCYN_ALU_FUNC_SUB: result = i_src_a - i_src_b;
            `PCYN_ALU_FUNC_AND: result = i_src_a & i_src_b;
            `PCYN_ALU_FUNC_OR:  result = i_src_a | i_src_b;
            `PCYN_ALU_FUNC_XOR: result = i_src_a ^ i_src_b;
            `PCYN_ALU_FUNC_SLL: result = i_src_a << i_shamt;
            `PCYN_ALU_FUNC_SRL: result = i_src_a >> i_shamt;
/* verilator lint_off WIDTH */
            `PCYN_ALU_FUNC_SRA: result = e_src_a >> i_shamt;
            `PCYN_ALU_FUNC_EQ:  result = i_src_a == i_src_b;
            `PCYN_ALU_FUNC_NE:  result = i_src_a != i_src_b;
            `PCYN_ALU_FUNC_LT:  result = s_src_a < s_src_b;
            `PCYN_ALU_FUNC_LTU: result = i_src_a < i_src_b;
            `PCYN_ALU_FUNC_GE:  result = s_src_a >= s_src_b;
            `PCYN_ALU_FUNC_GEU: result = i_src_a >= i_src_b;
/* verilator lint_on  WIDTH */
            default:            result = {(OPTN_DATA_WIDTH){1'b0}};
        endcase
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_valid <= 1'b0;
        else        o_valid <= ~i_flush & i_valid;
    end

    always_ff @(posedge clk) begin
        o_data     <= i_jmp ? i_iaddr + 4 : result;
        o_addr     <= i_jmp ? result : i_iaddr + i_imm_b;
        o_redirect <= i_jmp | (i_br & result[0]);
        o_tag      <= i_tag;
    end

endmodule
