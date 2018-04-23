#!/usr/bin/env python

import os
import argparse
import binascii

parser = argparse.ArgumentParser()
parser.add_argument("bin_dir", help="Path to RISCV assembly binary file or a directory containing binary files")
parser.add_argument("hex_dir", help="Path to place hex files")
args = parser.parse_args()

bin_files = []

if os.path.isdir(args.bin_dir):
    bin_files = [args.bin_dir + "/" + bin_file for bin_file in os.listdir(args.bin_dir)]
else:
    bin_files = [args.bin_dir]

print(bin_files)
for bin_file in bin_files:
    filename, ext = os.path.splitext(os.path.basename(bin_file))
    with open(args.hex_dir + "/" + filename + ".hex", "w") as d:
        with open(bin_file, "rb") as f:
            bytes_read = f.read()
            for b in bytes_read:
                d.write(binascii.hexlify(b) + '\n')
