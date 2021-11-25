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
