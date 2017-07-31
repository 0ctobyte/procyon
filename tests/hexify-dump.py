#!/usr/bin/env python

import argparse

parser = argparse.ArgumentParser()
parser.add_argument("dump_file", help="Path to RISCV assembly dump file")
args = parser.parse_args()

with open(args.dump_file.rsplit(".", 1)[0] + ".hex", "w") as d:
    insn_count = 0
    d.write('// instruction count:            \n')
    with open(args.dump_file, "r") as f:
        flag = False
        for line in f:
            l = line.rstrip().split()

            if len(l) == 2 and l[1].find("test") != -1:
                d.write("// " + ''.join(c for c in l[1] if c not in '<>:_') + '\n')
                flag = True
            elif len(l) == 0:
                flag = False       

            if flag and len(l) > 2:
                d.write(l[1] + "        " + "// " + ' '.join(l[2:]) + '\n')
                insn_count = insn_count + 1

    insn_count = insn_count + 11
    d.write('// FAIL\n')
    d.write('ae500193        // li	gp,0xfffffae5\n')
    d.write('00000063        // beq	zero,zero,0\n')
    d.write('00000013        // nop\n')
    d.write('00000013        // nop\n')
    d.write('00000013        // nop\n')
    d.write('// PASS\n')
    d.write('bd200193        // li	gp,0xfffffbd2\n')
    d.write('00000063        // beq	zero,zero,0\n')
    d.write('00000013        // nop\n')
    d.write('00000013        // nop\n')
    d.write('00000013        // nop\n')
    d.write('00000013        // nop\n')

    d.seek(23)
    d.write(str(insn_count))
