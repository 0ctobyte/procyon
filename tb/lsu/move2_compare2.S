#define MOVE_LOOP_COUNT 0x20
#define COMPARE_LOOP_COUNT 0x10
#define TOTAL_COUNT 0x2000

.section .text.init
.align 5
.global _start
_start:
    la x1, src
    la x2, dst
    li x3, TOTAL_COUNT

move_loop:
    lh x4, 0x0(x1)
    lh x5, 0x2(x1)
    lh x6, 0x4(x1)
    lh x7, 0x6(x1)
    lh x8, 0x8(x1)
    lh x9, 0xa(x1)
    lh x10, 0xc(x1)
    lh x11, 0xe(x1)
    lh x12, 0x10(x1)
    lh x13, 0x12(x1)
    lh x14, 0x14(x1)
    lh x15, 0x16(x1)
    lh x16, 0x18(x1)
    lh x17, 0x1a(x1)
    lh x18, 0x1c(x1)
    lh x19, 0x1e(x1)

    sh x4, 0x0(x2)
    sh x5, 0x2(x2)
    sh x6, 0x4(x2)
    sh x7, 0x6(x2)
    sh x8, 0x8(x2)
    sh x9, 0xa(x2)
    sh x10, 0xc(x2)
    sh x11, 0xe(x2)
    sh x12, 0x10(x2)
    sh x13, 0x12(x2)
    sh x14, 0x14(x2)
    sh x15, 0x16(x2)
    sh x16, 0x18(x2)
    sh x17, 0x1a(x2)
    sh x18, 0x1c(x2)
    sh x19, 0x1e(x2)

    addi x1, x1, MOVE_LOOP_COUNT
    addi x2, x2, MOVE_LOOP_COUNT
    addi x3, x3, -MOVE_LOOP_COUNT
    bne x3, x0, move_loop

    la x1, src
    la x2, dst
    li x3, TOTAL_COUNT

compare_loop:
    lh x4, 0x0(x1)
    lh x5, 0x2(x1)
    lh x6, 0x4(x1)
    lh x7, 0x6(x1)
    lh x8, 0x8(x1)
    lh x9, 0xa(x1)
    lh x10, 0xc(x1)
    lh x11, 0xe(x1)

    lh x12, 0x0(x2)
    lh x13, 0x2(x2)
    lh x14, 0x4(x2)
    lh x15, 0x6(x2)
    lh x16, 0x8(x2)
    lh x17, 0xa(x2)
    lh x18, 0xc(x2)
    lh x19, 0xe(x2)

    bne x4, x12, fail
    bne x5, x13, fail
    bne x6, x14, fail
    bne x7, x15, fail
    bne x8, x16, fail
    bne x9, x17, fail
    bne x10, x18, fail
    bne x11, x19, fail

    addi x1, x1, COMPARE_LOOP_COUNT
    addi x2, x2, COMPARE_LOOP_COUNT
    addi x3, x3, -COMPARE_LOOP_COUNT
    bne x3, x0, compare_loop

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
