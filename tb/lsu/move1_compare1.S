#define MOVE_LOOP_COUNT 0x10
#define COMPARE_LOOP_COUNT 0x8
#define TOTAL_COUNT 0x2000

.section .text.init
.align 5
.global _start
_start:
    la x1, src
    la x2, dst
    li x3, TOTAL_COUNT

move_loop:
    lb x4, 0x0(x1)
    lb x5, 0x1(x1)
    lb x6, 0x2(x1)
    lb x7, 0x3(x1)
    lb x8, 0x4(x1)
    lb x9, 0x5(x1)
    lb x10, 0x6(x1)
    lb x11, 0x7(x1)
    lb x12, 0x8(x1)
    lb x13, 0x9(x1)
    lb x14, 0xa(x1)
    lb x15, 0xb(x1)
    lb x16, 0xc(x1)
    lb x17, 0xd(x1)
    lb x18, 0xe(x1)
    lb x19, 0xf(x1)

    sb x4, 0x0(x2)
    sb x5, 0x1(x2)
    sb x6, 0x2(x2)
    sb x7, 0x3(x2)
    sb x8, 0x4(x2)
    sb x9, 0x5(x2)
    sb x10, 0x6(x2)
    sb x11, 0x7(x2)
    sb x12, 0x8(x2)
    sb x13, 0x9(x2)
    sb x14, 0xa(x2)
    sb x15, 0xb(x2)
    sb x16, 0xc(x2)
    sb x17, 0xd(x2)
    sb x18, 0xe(x2)
    sb x19, 0xf(x2)

    addi x1, x1, MOVE_LOOP_COUNT
    addi x2, x2, MOVE_LOOP_COUNT
    addi x3, x3, -MOVE_LOOP_COUNT
    bne x3, x0, move_loop

    la x1, src
    la x2, dst
    li x3, TOTAL_COUNT

compare_loop:
    lb x4, 0x0(x1)
    lb x5, 0x1(x1)
    lb x6, 0x2(x1)
    lb x7, 0x3(x1)
    lb x8, 0x4(x1)
    lb x9, 0x5(x1)
    lb x10, 0x6(x1)
    lb x11, 0x7(x1)

    lb x12, 0x0(x2)
    lb x13, 0x1(x2)
    lb x14, 0x2(x2)
    lb x15, 0x3(x2)
    lb x16, 0x4(x2)
    lb x17, 0x5(x2)
    lb x18, 0x6(x2)
    lb x19, 0x7(x2)

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
