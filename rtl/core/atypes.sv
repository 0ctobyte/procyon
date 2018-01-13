// user-defined types and interfaces

`include "common.svh"

package procyon_types;

    typedef logic [`ADDR_WIDTH-1:0]             procyon_addr_t;
    typedef logic [`DATA_WIDTH-1:0]             procyon_data_t;
    typedef logic [`TAG_WIDTH-1:0]              procyon_tag_t;
    typedef logic [`REG_ADDR_WIDTH-1:0]         procyon_reg_t;
    typedef logic [`WORD_SIZE-1:0]              procyon_word_t;

    typedef logic [`DC_LINE_WIDTH-1:0]          procyon_dc_line_t;
    typedef logic [`DC_SET_WIDTH-1:0]           procyon_dc_set_t;
    typedef logic [`DC_TAG_WIDTH-1:0]           procyon_dc_tag_t;

    typedef logic [`TAG_WIDTH:0]                procyon_tagp_t;
    typedef logic [`ADDR_WIDTH+`DATA_WIDTH-1:0] procyon_addr_data_t;
    typedef logic signed [`DATA_WIDTH-1:0]      procyon_signed_data_t;
    typedef logic [4:0]                         procyon_shamt_t;

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

    typedef enum logic [2:0] {
        LSU_FUNC_LB   = 3'b000,
        LSU_FUNC_LH   = 3'b001,
        LSU_FUNC_LW   = 3'b010,
        LSU_FUNC_LBU  = 3'b011,
        LSU_FUNC_LHU  = 3'b100,
        LSU_FUNC_SB   = 3'b101,
        LSU_FUNC_SH   = 3'b110,
        LSU_FUNC_SW   = 3'b111
    } procyon_lsu_func_t;

endpackage
