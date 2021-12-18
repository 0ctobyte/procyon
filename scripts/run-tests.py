#!/usr/bin/env python3

import os
import sys
import subprocess
import argparse
import tempfile
import timeit
from tabulate import tabulate

parser = argparse.ArgumentParser()
parser.add_argument("sim_dir", help="Path to systemc simulation executable to run or directory containing multiple directories with a sytemc simulation executable in each sub-directory")
parser.add_argument("tests_dir", help="Path to RISCV elf/binary file or a directory containing elf/binary files")
parser.add_argument("-t", "--timeout", metavar="<seconds>", default=3, type=int, help="Specify a timeout in seconds to allow an architectural test to run for before it is killed and considered a failed test")
parser.add_argument("-i", "--include", metavar="<pattern>", action="append", help="Specify a filename filter. Filenames that contain the corresponding text will be included in the test")
parser.add_argument("-e", "--exclude", metavar="<pattern>", action="append", help="Specify a filename filter. Filenames that contain the corresponding text will be excluded in the test")
parser.add_argument("-x", "--executable", metavar="<filename>", default="Vdut", help="If a simulation directory with sub-directories was specified, then use this arg to specify the simulation executable name in each sub-directory. The name must be exactly the same")
args = parser.parse_args()

def run_tests(sim_bin, test_list):
    test_passes = 0
    test_results = []

    for test in test_list:
        test_path = args.tests_dir + "/" + test if os.path.isdir(args.tests_dir) else args.tests_dir

        t0 = timeit.default_timer()
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
            result = subprocess.run([os.path.abspath(sim_bin), test_path], cwd=os.path.dirname(sim_bin), capture_output=True, text=True, timeout=args.timeout)
        except subprocess.TimeoutExpired:
            t1 = timeit.default_timer()
            test_results += [test_result + ["HANG", "--", "--", "--", str(t1 - t0), sim_bin]]
            print(".", end="", flush=True)
            continue

        t1 = timeit.default_timer()
        if result.returncode == 0:
            test_result += ["PASS"]
            test_passes = test_passes + 1
        else:
            test_result += ["FAIL"]

        test_details = result.stdout.split("\n")[3].split(" ")
        test_result += [test_details[1], test_details[3], test_details[5], str(t1 - t0), sim_bin]

        test_results += [test_result]
        print(".", end="", flush=True)

    return (test_results, test_passes)

test_list = []

if os.path.isdir(args.tests_dir):
    test_list = os.listdir(args.tests_dir)

    # filter out arch tests
    if args.include != None:
        test_list = [test for test in test_list for include in args.include if include in test]

    if args.exclude != None:
        excluded_list = [test for test in test_list for exclude in args.exclude if exclude in test]
        test_list = list(set(test_list) - set(excluded_list))
else:
    test_list = [os.path.basename(args.tests_dir)]

test_list = sorted(test_list)
test_results = []
test_passes = 0

print("RUNNING TESTS", end="", flush=True)

if os.path.isdir(args.sim_dir):
    dir_list = os.listdir(args.sim_dir)
    for d in dir_list:
        results, passes = run_tests(os.path.join(args.sim_dir, d, args.executable), test_list)
        test_results += results
        test_passes += passes
else:
    test_results, test_passes = run_tests(args.sim_dir, test_list)

print()
print(tabulate(test_results, headers=["NAME", "RESULT", "#INSTRUCTIONS", "#CYCLES", "CPI", "SIM TIME", "MODEL"]))
print(str(test_passes) + "/" + str(len(test_results)) + " PASSED")
