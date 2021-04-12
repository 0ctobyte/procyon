#!/usr/bin/env python3

import os
import tempfile
import subprocess
import argparse
import binascii

parser = argparse.ArgumentParser()
parser.add_argument("dir", help="Path to RISCV elf/binary file or a directory containing elf/binary files")
parser.add_argument("hex_dir", help="Path to place hex files")
args = parser.parse_args()

rv_programs = []

if os.path.isdir(args.dir):
    rv_programs = [args.dir + "/" + program for program in os.listdir(args.dir)]
else:
    rv_programs = [args.dir]

for program in rv_programs:
    filename, ext = os.path.splitext(os.path.basename(program))

    print("Convert " + filename, end=" -> ")

    # Convert to binary
    if ext != ".bin":
        f = filename + ".bin"
        bin_file = tempfile.gettempdir() + "/" + f

        print(bin_file, end=" -> ")

        result = subprocess.call(["riscv64-unknown-elf-objcopy", "-O", "binary", program, bin_file])
        if result != 0:
            exit(err)
        program = bin_file

    hex_file = filename + ".hex"

    print(hex_file)
    with open(args.hex_dir + "/" + hex_file, "w") as d:
        with open(program, "rb") as f:
            d.write(f.read().hex(sep='\n', bytes_per_sep=1))
