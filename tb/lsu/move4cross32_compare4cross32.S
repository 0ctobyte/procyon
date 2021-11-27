#define MOVE_LOOP_COUNT 0x200
#define COMPARE_LOOP_COUNT 0x200
#define TOTAL_COUNT 0x2000

.section .text.init
.align 5
.global _start
_start:
    la x1, src
    la x2, dst
    li x3, TOTAL_COUNT
    li x20, 0xcafecafe

move_loop:
    sw x20, 0xe(x2)
    sw x20, 0x2e(x2)
    sw x20, 0x4e(x2)
    sw x20, 0x6e(x2)
    sw x20, 0x8e(x2)
    sw x20, 0xae(x2)
    sw x20, 0xce(x2)
    sw x20, 0xee(x2)
    sw x20, 0x10e(x2)
    sw x20, 0x12e(x2)
    sw x20, 0x14e(x2)
    sw x20, 0x16e(x2)
    sw x20, 0x18e(x2)
    sw x20, 0x1ae(x2)
    sw x20, 0x1ce(x2)
    sw x20, 0x1ee(x2)

    addi x1, x1, MOVE_LOOP_COUNT
    addi x2, x2, MOVE_LOOP_COUNT
    addi x3, x3, -MOVE_LOOP_COUNT
    bne x3, x0, move_loop

    la x1, src
    la x2, dst
    li x3, TOTAL_COUNT

compare_loop:
    lw x4, 0xe(x1)
    lw x5, 0x2e(x1)
    lw x6, 0x4e(x1)
    lw x7, 0x6e(x1)
    lw x8, 0x8e(x1)
    lw x9, 0xae(x1)
    lw x10, 0xce(x1)
    lw x11, 0xee(x1)
    lw x12, 0x10e(x1)
    lw x13, 0x12e(x1)
    lw x14, 0x14e(x1)
    lw x15, 0x16e(x1)
    lw x16, 0x18e(x1)
    lw x17, 0x1ae(x1)
    lw x18, 0x1ce(x1)
    lw x19, 0x1ee(x1)

    bne x4, x20, fail
    bne x5, x20, fail
    bne x6, x20, fail
    bne x7, x20, fail
    bne x8, x20, fail
    bne x9, x20, fail
    bne x10, x20, fail
    bne x11, x20, fail
    bne x12, x20, fail
    bne x13, x20, fail
    bne x14, x20, fail
    bne x15, x20, fail
    bne x16, x20, fail
    bne x17, x20, fail
    bne x18, x20, fail
    bne x19, x20, fail

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
