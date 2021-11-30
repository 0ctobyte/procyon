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
        rv_programs = [test for test in rv_programs for exclude in args.exclude if exclude not in test]
    rv_programs = [args.dir + "/" + program for program in rv_programs]
else:
    rv_programs = [args.dir]

for program in rv_programs:
    filename, ext = os.path.splitext(os.path.basename(program))
    print("Convert " + program, end=" -> ")

    if ext == ".hex":
        continue

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
            d.write(f.read().hex(sep='\n', bytes_per_sep=1))
