#define MOVE_LOOP_COUNT 0x40
#define COMPARE_LOOP_COUNT 0x20
#define TOTAL_COUNT 0x2000
#define UNALIGNED_OFFSET 0x2

.section .text.init
.align 5
.global _start
_start:
    la x1, src
    la x2, dst
    addi x1, x1, UNALIGNED_OFFSET
    addi x2, x2, UNALIGNED_OFFSET
    li x3, TOTAL_COUNT

move_loop:
    lw x4, 0x0(x1)
    lw x5, 0x4(x1)
    lw x6, 0x8(x1)
    lw x7, 0xc(x1)
    lw x8, 0x10(x1)
    lw x9, 0x14(x1)
    lw x10, 0x18(x1)
    lw x11, 0x1c(x1)
    lw x12, 0x20(x1)
    lw x13, 0x24(x1)
    lw x14, 0x28(x1)
    lw x15, 0x2c(x1)
    lw x16, 0x30(x1)
    lw x17, 0x34(x1)
    lw x18, 0x38(x1)
    lw x19, 0x3c(x1)

    sw x4, 0x0(x2)
    sw x5, 0x4(x2)
    sw x6, 0x8(x2)
    sw x7, 0xc(x2)
    sw x8, 0x10(x2)
    sw x9, 0x14(x2)
    sw x10, 0x18(x2)
    sw x11, 0x1c(x2)
    sw x12, 0x20(x2)
    sw x13, 0x24(x2)
    sw x14, 0x28(x2)
    sw x15, 0x2c(x2)
    sw x16, 0x30(x2)
    sw x17, 0x34(x2)
    sw x18, 0x38(x2)
    sw x19, 0x3c(x2)

    addi x1, x1, MOVE_LOOP_COUNT
    addi x2, x2, MOVE_LOOP_COUNT
    addi x3, x3, -MOVE_LOOP_COUNT
    bne x3, x0, move_loop

    la x1, src
    la x2, dst
    addi x1, x1, UNALIGNED_OFFSET
    addi x2, x2, UNALIGNED_OFFSET
    li x3, TOTAL_COUNT

compare_loop:
    lw x4, 0x0(x1)
    lw x5, 0x4(x1)
    lw x6, 0x8(x1)
    lw x7, 0xc(x1)
    lw x8, 0x10(x1)
    lw x9, 0x14(x1)
    lw x10, 0x18(x1)
    lw x11, 0x1c(x1)

    lw x12, 0x0(x2)
    lw x13, 0x4(x2)
    lw x14, 0x8(x2)
    lw x15, 0xc(x2)
    lw x16, 0x10(x2)
    lw x17, 0x14(x2)
    lw x18, 0x18(x2)
    lw x19, 0x1c(x2)

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
