// user-defined types and interfaces

`include "common.svh"

package procyon_types;

    typedef logic [`ADDR_WIDTH-1:0]                procyon_addr_t;
    typedef logic [`DATA_WIDTH-1:0]                procyon_data_t;
    typedef logic [`TAG_WIDTH-1:0]                 procyon_tag_t;
    typedef logic [`REG_ADDR_WIDTH-1:0]            procyon_reg_t;
    typedef logic [`WORD_SIZE-1:0]                 procyon_byte_select_t;
    typedef logic [`SQ_DEPTH-1:0]                  procyon_sq_select_t;
    typedef logic [`LQ_DEPTH-1:0]                  procyon_lq_select_t;

    typedef logic [`TAG_WIDTH:0]                   procyon_tagp_t;
    typedef logic [`ADDR_WIDTH+`DATA_WIDTH-1:0]    procyon_addr_data_t;
    typedef logic signed [`DATA_WIDTH-1:0]         procyon_signed_data_t;
    typedef logic [4:0]                            procyon_shamt_t;

    typedef logic [`ADDR_WIDTH-1:`DC_OFFSET_WIDTH] procyon_mhq_addr_t;
    typedef logic [`MHQ_TAG_WIDTH-1:0]             procyon_mhq_tag_t;
    typedef logic [`MHQ_TAG_WIDTH:0]               procyon_mhq_tagp_t;
    typedef logic [`MHQ_DEPTH-1:0]                 procyon_mhq_tag_select_t;

    typedef logic [`DC_LINE_WIDTH-1:0]             procyon_cacheline_t;
    typedef logic [`DC_TAG_WIDTH-1:0]              procyon_dc_tag_t;
    typedef logic [`DC_INDEX_WIDTH-1:0]            procyon_dc_index_t;
    typedef logic [`DC_OFFSET_WIDTH-1:0]           procyon_dc_offset_t;
    typedef logic [`DC_LINE_SIZE-1:0]              procyon_dc_byte_select_t;

    typedef logic [`WB_ADDR_WIDTH-1:0]             wb_addr_t;
    typedef logic [`WB_DATA_WIDTH-1:0]             wb_data_t;
    typedef logic [`WB_DATA_WIDTH/8-1:0]           wb_byte_select_t;

    typedef enum logic [1:0] {
        ROB_OP_INT = 2'b00,
        ROB_OP_BR  = 2'b01,
        ROB_OP_LD  = 2'b10,
        ROB_OP_ST  = 2'b11
    } procyon_rob_op_t;

    typedef enum logic [6:0] {
        OPCODE_OPIMM  = 7'b0010011,
        OPCODE_LUI    = 7'b0110111,
        OPCODE_AUIPC  = 7'b0010111,
        OPCODE_OP     = 7'b0110011,
        OPCODE_JAL    = 7'b1101111,
        OPCODE_JALR   = 7'b1100111,
        OPCODE_BRANCH = 7'b1100011,
        OPCODE_LOAD   = 7'b0000011,
        OPCODE_STORE  = 7'b0100011
    } procyon_opcode_t;

    typedef enum logic [3:0] {
        ALU_FUNC_ADD  = 4'b0000,
        ALU_FUNC_SUB  = 4'b0001,
        ALU_FUNC_AND  = 4'b0010,
        ALU_FUNC_OR   = 4'b0011,
        ALU_FUNC_XOR  = 4'b0100,
        ALU_FUNC_SLL  = 4'b0101,
        ALU_FUNC_SRL  = 4'b0110,
        ALU_FUNC_SRA  = 4'b0111,
        ALU_FUNC_EQ   = 4'b1000,
        ALU_FUNC_NE   = 4'b1001,
        ALU_FUNC_LT   = 4'b1010,
        ALU_FUNC_LTU  = 4'b1011,
        ALU_FUNC_GE   = 4'b1100,
        ALU_FUNC_GEU  = 4'b1101
    } procyon_alu_func_t;

    typedef enum logic [3:0] {
        LSU_FUNC_LB   = 4'b0000,
        LSU_FUNC_LH   = 4'b0001,
        LSU_FUNC_LW   = 4'b0010,
        LSU_FUNC_LBU  = 4'b0011,
        LSU_FUNC_LHU  = 4'b0100,
        LSU_FUNC_SB   = 4'b0101,
        LSU_FUNC_SH   = 4'b0110,
        LSU_FUNC_SW   = 4'b0111,
        LSU_FUNC_FILL = 4'b1000
    } procyon_lsu_func_t;

    typedef struct packed {
        logic                           valid;
        logic                           dirty;
        procyon_mhq_addr_t              addr;
        procyon_cacheline_t             data;
        procyon_dc_byte_select_t        byte_updated;
    } procyon_mhq_entry_t;

    function logic mux4_1b (
        input logic       i_data0,
        input logic       i_data1,
        input logic       i_data2,
        input logic       i_data3,
        input logic [1:0] i_sel
    );

        case (i_sel)
            2'b00: mux4_1b = i_data0;
            2'b01: mux4_1b = i_data1;
            2'b10: mux4_1b = i_data2;
            2'b11: mux4_1b = i_data3;
        endcase

    endfunction

    function logic [1:0] mux4_2b (
        input logic [1:0] i_data0,
        input logic [1:0] i_data1,
        input logic [1:0] i_data2,
        input logic [1:0] i_data3,
        input logic [1:0] i_sel
    );

        case (i_sel)
            2'b00: mux4_2b = i_data0;
            2'b01: mux4_2b = i_data1;
            2'b10: mux4_2b = i_data2;
            2'b11: mux4_2b = i_data3;
        endcase

    endfunction

    function logic [3:0] mux4_4b (
        input logic [3:0] i_data0,
        input logic [3:0] i_data1,
        input logic [3:0] i_data2,
        input logic [3:0] i_data3,
        input logic [1:0] i_sel
    );

        case (i_sel)
            2'b00: mux4_4b = i_data0;
            2'b01: mux4_4b = i_data1;
            2'b10: mux4_4b = i_data2;
            2'b11: mux4_4b = i_data3;
        endcase

    endfunction

    function logic [7:0] mux4_8b (
        input logic [7:0] i_data0,
        input logic [7:0] i_data1,
        input logic [7:0] i_data2,
        input logic [7:0] i_data3,
        input logic [1:0] i_sel
    );

        case (i_sel)
            2'b00: mux4_8b = i_data0;
            2'b01: mux4_8b = i_data1;
            2'b10: mux4_8b = i_data2;
            2'b11: mux4_8b = i_data3;
        endcase

    endfunction

    function logic [`ADDR_WIDTH-1:0] mux4_addr (
        input logic [`ADDR_WIDTH-1:0] i_data0,
        input logic [`ADDR_WIDTH-1:0] i_data1,
        input logic [`ADDR_WIDTH-1:0] i_data2,
        input logic [`ADDR_WIDTH-1:0] i_data3,
        input logic [1:0]             i_sel
    );

        case (i_sel)
            2'b00: mux4_addr = i_data0;
            2'b01: mux4_addr = i_data1;
            2'b10: mux4_addr = i_data2;
            2'b11: mux4_addr = i_data3;
        endcase

    endfunction

    function logic [`DATA_WIDTH-1:0] mux4_data (
        input logic [`DATA_WIDTH-1:0] i_data0,
        input logic [`DATA_WIDTH-1:0] i_data1,
        input logic [`DATA_WIDTH-1:0] i_data2,
        input logic [`DATA_WIDTH-1:0] i_data3,
        input logic [1:0]             i_sel
    );

        case (i_sel)
            2'b00: mux4_data = i_data0;
            2'b01: mux4_data = i_data1;
            2'b10: mux4_data = i_data2;
            2'b11: mux4_data = i_data3;
        endcase

    endfunction

    function logic [`TAG_WIDTH-1:0] mux4_tag (
        input logic [`TAG_WIDTH-1:0] i_data0,
        input logic [`TAG_WIDTH-1:0] i_data1,
        input logic [`TAG_WIDTH-1:0] i_data2,
        input logic [`TAG_WIDTH-1:0] i_data3,
        input logic [1:0]             i_sel
    );

        case (i_sel)
            2'b00: mux4_tag = i_data0;
            2'b01: mux4_tag = i_data1;
            2'b10: mux4_tag = i_data2;
            2'b11: mux4_tag = i_data3;
        endcase

    endfunction

endpackage
