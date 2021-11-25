#define FILL_LOOP_COUNT 0x100
#define OUTER_LOOP_COUNT 0x20
#define MOVE_INNER_LOOP_COUNT 0x200
#define COMPARE_INNER_LOOP_COUNT 0x100
#define TOTAL_COUNT 0x2000

.section .text.init
.align 5
.global _start
_start:
    li x20, OUTER_LOOP_COUNT
    li x21, 0x0
    li x22, 0xf0f0f0f0
    li x23, 0x0f0f0f0f

    la x1, src
    la x2, dst
    li x3, TOTAL_COUNT

fill_loop:
    sw x22, 0x0(x1)
    sw x22, 0x4(x1)
    sw x22, 0x8(x1)
    sw x22, 0xc(x1)
    sw x22, 0x10(x1)
    sw x22, 0x14(x1)
    sw x22, 0x18(x1)
    sw x22, 0x1c(x1)
    sw x22, 0x20(x1)
    sw x22, 0x24(x1)
    sw x22, 0x28(x1)
    sw x22, 0x2c(x1)
    sw x22, 0x30(x1)
    sw x22, 0x34(x1)
    sw x22, 0x38(x1)
    sw x22, 0x3c(x1)
    sw x22, 0x40(x1)
    sw x22, 0x44(x1)
    sw x22, 0x48(x1)
    sw x22, 0x4c(x1)
    sw x22, 0x50(x1)
    sw x22, 0x54(x1)
    sw x22, 0x58(x1)
    sw x22, 0x5c(x1)
    sw x22, 0x60(x1)
    sw x22, 0x64(x1)
    sw x22, 0x68(x1)
    sw x22, 0x6c(x1)
    sw x22, 0x70(x1)
    sw x22, 0x74(x1)
    sw x22, 0x78(x1)
    sw x22, 0x7c(x1)
    sw x22, 0x80(x1)
    sw x22, 0x84(x1)
    sw x22, 0x88(x1)
    sw x22, 0x8c(x1)
    sw x22, 0x90(x1)
    sw x22, 0x94(x1)
    sw x22, 0x98(x1)
    sw x22, 0x9c(x1)
    sw x22, 0xa0(x1)
    sw x22, 0xa4(x1)
    sw x22, 0xa8(x1)
    sw x22, 0xac(x1)
    sw x22, 0xb0(x1)
    sw x22, 0xb4(x1)
    sw x22, 0xb8(x1)
    sw x22, 0xbc(x1)
    sw x22, 0xc0(x1)
    sw x22, 0xc4(x1)
    sw x22, 0xc8(x1)
    sw x22, 0xcc(x1)
    sw x22, 0xd0(x1)
    sw x22, 0xd4(x1)
    sw x22, 0xd8(x1)
    sw x22, 0xdc(x1)
    sw x22, 0xe0(x1)
    sw x22, 0xe4(x1)
    sw x22, 0xe8(x1)
    sw x22, 0xec(x1)
    sw x22, 0xf0(x1)
    sw x22, 0xf4(x1)
    sw x22, 0xf8(x1)
    sw x22, 0xfc(x1)

    sw x23, 0x0(x2)
    sw x23, 0x4(x2)
    sw x23, 0x8(x2)
    sw x23, 0xc(x2)
    sw x23, 0x10(x2)
    sw x23, 0x14(x2)
    sw x23, 0x18(x2)
    sw x23, 0x1c(x2)
    sw x23, 0x20(x2)
    sw x23, 0x24(x2)
    sw x23, 0x28(x2)
    sw x23, 0x2c(x2)
    sw x23, 0x30(x2)
    sw x23, 0x34(x2)
    sw x23, 0x38(x2)
    sw x23, 0x3c(x2)
    sw x23, 0x40(x2)
    sw x23, 0x44(x2)
    sw x23, 0x48(x2)
    sw x23, 0x4c(x2)
    sw x23, 0x50(x2)
    sw x23, 0x54(x2)
    sw x23, 0x58(x2)
    sw x23, 0x5c(x2)
    sw x23, 0x60(x2)
    sw x23, 0x64(x2)
    sw x23, 0x68(x2)
    sw x23, 0x6c(x2)
    sw x23, 0x70(x2)
    sw x23, 0x74(x2)
    sw x23, 0x78(x2)
    sw x23, 0x7c(x2)
    sw x23, 0x80(x2)
    sw x23, 0x84(x2)
    sw x23, 0x88(x2)
    sw x23, 0x8c(x2)
    sw x23, 0x90(x2)
    sw x23, 0x94(x2)
    sw x23, 0x98(x2)
    sw x23, 0x9c(x2)
    sw x23, 0xa0(x2)
    sw x23, 0xa4(x2)
    sw x23, 0xa8(x2)
    sw x23, 0xac(x2)
    sw x23, 0xb0(x2)
    sw x23, 0xb4(x2)
    sw x23, 0xb8(x2)
    sw x23, 0xbc(x2)
    sw x23, 0xc0(x2)
    sw x23, 0xc4(x2)
    sw x23, 0xc8(x2)
    sw x23, 0xcc(x2)
    sw x23, 0xd0(x2)
    sw x23, 0xd4(x2)
    sw x23, 0xd8(x2)
    sw x23, 0xdc(x2)
    sw x23, 0xe0(x2)
    sw x23, 0xe4(x2)
    sw x23, 0xe8(x2)
    sw x23, 0xec(x2)
    sw x23, 0xf0(x2)
    sw x23, 0xf4(x2)
    sw x23, 0xf8(x2)
    sw x23, 0xfc(x2)

    addi x1, x1, FILL_LOOP_COUNT
    addi x2, x2, FILL_LOOP_COUNT
    addi x3, x3, -FILL_LOOP_COUNT
    bne x3, x0, fill_loop

outer_move_loop:
    la x1, src
    la x2, dst
    li x3, TOTAL_COUNT

    add x1, x1, x21
    add x2, x2, x21

inner_move_loop:
    lw x4, 0x0(x1)
    lw x5, 0x20(x1)
    lw x6, 0x40(x1)
    lw x7, 0x60(x1)
    lw x8, 0x80(x1)
    lw x9, 0xa0(x1)
    lw x10, 0xc0(x1)
    lw x11, 0xe0(x1)
    lw x12, 0x100(x1)
    lw x13, 0x120(x1)
    lw x14, 0x140(x1)
    lw x15, 0x160(x1)
    lw x16, 0x180(x1)
    lw x17, 0x1a0(x1)
    lw x18, 0x1c0(x1)
    lw x19, 0x1e0(x1)

    sw x4, 0x0(x2)
    sw x5, 0x20(x2)
    sw x6, 0x40(x2)
    sw x7, 0x60(x2)
    sw x8, 0x80(x2)
    sw x9, 0xa0(x2)
    sw x10, 0xc0(x2)
    sw x11, 0xe0(x2)
    sw x12, 0x100(x2)
    sw x13, 0x120(x2)
    sw x14, 0x140(x2)
    sw x15, 0x160(x2)
    sw x16, 0x180(x2)
    sw x17, 0x1a0(x2)
    sw x18, 0x1c0(x2)
    sw x19, 0x1e0(x2)

    addi x1, x1, MOVE_INNER_LOOP_COUNT
    addi x2, x2, MOVE_INNER_LOOP_COUNT
    addi x3, x3, -MOVE_INNER_LOOP_COUNT
    bne x3, x0, inner_move_loop

    addi x21, x21, 0x4
    bne x20, x21, outer_move_loop

    li x20, OUTER_LOOP_COUNT
    li x21, 0x0

outer_compare_loop:
    la x1, src
    la x2, dst
    li x3, TOTAL_COUNT

    add x1, x1, x21
    add x2, x2, x21

inner_compare_loop:
    lw x4, 0x0(x1)
    lw x5, 0x20(x1)
    lw x6, 0x40(x1)
    lw x7, 0x60(x1)
    lw x8, 0x80(x1)
    lw x9, 0xa0(x1)
    lw x10, 0xc0(x1)
    lw x11, 0xe0(x1)

    lw x12, 0x0(x2)
    lw x13, 0x20(x2)
    lw x14, 0x40(x2)
    lw x15, 0x60(x2)
    lw x16, 0x80(x2)
    lw x17, 0xa0(x2)
    lw x18, 0xc0(x2)
    lw x19, 0xe0(x2)

    bne x4, x12, fail
    bne x5, x13, fail
    bne x6, x14, fail
    bne x7, x15, fail
    bne x8, x16, fail
    bne x9, x17, fail
    bne x10, x18, fail
    bne x11, x19, fail

    addi x1, x1, COMPARE_INNER_LOOP_COUNT
    addi x2, x2, COMPARE_INNER_LOOP_COUNT
    addi x3, x3, -COMPARE_INNER_LOOP_COUNT
    bne x3, x0, inner_compare_loop

    addi x21, x21, 0x4
    bne x20, x21, outer_compare_loop

pass:
    li tp, 0x4a33
1:  beqz zero, 1b
fail:
    li tp, 0xfae1
1:  beqz zero, 1b

.section .data
# 8KB of data
.align 5
src:
.rept 256
.word 0xdeadbeef
.word 0xdeadbeef
.word 0xdeadbeef
.word 0xdeadbeef
.word 0xdeadbeef
.word 0xdeadbeef
.word 0xdeadbeef
.word 0xdeadbeef
.endr
# 8KB of data
.align 5
dst:
.rept 256
.word 0x0
.word 0x0
.word 0x0
.word 0x0
.word 0x0
.word 0x0
.word 0x0
.word 0x0
.endr
