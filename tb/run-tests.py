#!/usr/bin/env python3

import os
import sys
import subprocess
import argparse
import tempfile
from tabulate import tabulate

parser = argparse.ArgumentParser()
parser.add_argument("sim_bin", help="Path to systemc simulation executable to run")
parser.add_argument("tests_dir", help="Path to simulation test directory containing binaries of architectural tests to run")
parser.add_argument("--timeout", default=3, type=int, help="Specify a timeout in seconds to allow an architectural test to run for before it is killed and considered a failed test")
parser.add_argument("-i", "--include", action="append", help="Specify a filename filter. Filenames that contain the corresponding text will be included in the test")
parser.add_argument("-e", "--exclude", action="append", help="Specify a filename filter. Filenames that contain the corresponding text will be excluded in the test")
args = parser.parse_args()

test_list = os.listdir(args.tests_dir)

# filter out arch tests
if args.include != None:
    test_list = [test for test in test_list for include in args.include if include in test]

if args.exclude != None:
    test_list = [test for test in test_list for exclude in args.exclude if exclude not in test]

test_passes = 0

print("RUNNING TESTS", end="", flush=True)

test_results = []

for test in test_list:
    test_path = args.tests_dir + "/" + test

    # Convert to binary
    if test.find(".bin") == -1:
        test = test + ".bin"
        test_bin = tempfile.gettempdir() + "/" + test
        result = subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary", test_path, test_bin])
        if result.returncode != 0:
            exit(result.returncode)
        test_path = test_bin

    test_result = [test]

    try:
        result = subprocess.run([args.sim_bin, test_path], capture_output=True, text=True, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        test_results += [test_result + ["HANG", "--", "--", "--"]]
        print(".", end="", flush=True)
        continue

    if result.returncode != 0:
        test_result += ["PASS"]
        test_passes = test_passes + 1
    else:
        test_result += ["FAIL"]

    test_details = result.stdout.split("\n")[3].split(" ")
    test_result += [test_details[1], test_details[3], test_details[5]]

    test_results += [test_result]
    print(".", end="", flush=True)

print()
print(tabulate(test_results, headers=["NAME", "RESULT", "#INSTRUCTIONS", "#CYCLES", "CPI"]))
print(str(test_passes) + "/" + str(len(test_list)) + " PASSED")