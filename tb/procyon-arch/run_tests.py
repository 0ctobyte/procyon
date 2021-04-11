#!/usr/bin/env python3

import os
import sys
import subprocess
import argparse
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("sim_bin", help="Path to systemc simulation executable to run")
parser.add_argument("tests_dir", help="Path to simulation test directory containing binaries of architectural tests to run")
args = parser.parse_args()

test_list = os.listdir(args.tests_dir)

# filter out unsupported arch tests
test_list = [test for test in test_list if (test.find("32ui-px-") >= 0 and test.find(".dump") == -1)]
test_list = [test for test in test_list if test.find("fence") == -1]

test_passes = 0

print("PROCYON ARCH TESTS")

for test in test_list:
    test_path = args.tests_dir + "/" + test

    # Convert to binary
    if test.find(".bin") == -1:
        test = test + ".bin"
        test_bin = tempfile.gettempdir() + "/" + test
        err = subprocess.call(["riscv64-unknown-elf-objcopy", "-O", "binary", test_path, test_bin])
        if err != 0:
            exit(err)
        test_path = test_bin

    print(test, end="\t")
    sys.stdout.flush()

    err = subprocess.call([args.sim_bin, test_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if err != 0:
        print("PASS")
        test_passes = test_passes + 1
    else:
        print("FAIL")

print("PROCYON ARCH TESTS: " + str(test_passes) + "/" + str(len(test_list)) + " PASSED")
