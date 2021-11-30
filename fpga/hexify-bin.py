#!/usr/bin/env python3

import os
import sys
import tempfile
import subprocess
import argparse
import binascii

parser = argparse.ArgumentParser()
parser.add_argument("dir", help="Path to RISCV elf/binary file or a directory containing elf/binary files")
parser.add_argument("hex_dir", help="Path to place hex files")
parser.add_argument("-w", "--hexwidth", default=1, type=int, help="Specify the width of each hex string per line")
parser.add_argument("-i", "--include", action="append", help="Specify a filename filter. Filenames that contain the corresponding text will be included in the test")
parser.add_argument("-e", "--exclude", action="append", help="Specify a filename filter. Filenames that contain the corresponding text will be excluded in the test")
args = parser.parse_args()

rv_programs = []

if os.path.isdir(args.dir):
    rv_programs = os.listdir(args.dir)
    # filter out programs
    if args.include != None:
        rv_programs = [test for test in rv_programs for include in args.include if include in test]
    if args.exclude != None:
        excluded_programs = [test for test in rv_programs for exclude in args.exclude if exclude in test]
        rv_programs = list(set(rv_programs) - set(excluded_programs))
    rv_programs = [args.dir + "/" + program for program in rv_programs]
else:
    rv_programs = [args.dir]

print(rv_programs)
for program in rv_programs:
    filename, ext = os.path.splitext(os.path.basename(program))
    print("Convert " + program, end=" -> ")

    # Convert to binary
    bin_file = tempfile.gettempdir() + "/" + filename + ".bin"

    print(bin_file, end=" -> ")

    result = subprocess.call(["riscv64-unknown-elf-objcopy", "-O", "binary", program, bin_file])
    if result != 0:
        sys.exit(-1)

    hex_file = filename + ".hex"

    print(hex_file)
    with open(args.hex_dir + "/" + hex_file, "w") as d:
        with open(bin_file, "rb") as f:
            b = f.read()
            l = len(b)

            aligned_l = (l + (args.hexwidth - 1)) & ~(args.hexwidth - 1)
            aligned_b = b + bytes((aligned_l - l) * [0])

            d.write(aligned_b.hex(sep='\n', bytes_per_sep=args.hexwidth))
