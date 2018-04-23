#!/usr/bin/env python

import os
import subprocess
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("sim_bin", help="Path to systemc simulation executable to run")
parser.add_argument("tests_dir", help="Path to simulation test directory containing binaries of architectural tests to run")
args = parser.parse_args()

test_list = os.listdir(args.tests_dir)
test_count = 0

print("PROCYON ARCH TESTS: START")

for test in test_list:
    test_path = args.tests_dir+"/"+test
    print("PROCYON ARCH TEST: " + test_path)
    err = subprocess.call([args.sim_bin, test_path])
    if err == 0:
        test_count = test_count + 1

print("PROCYON ARCH TESTS: " + str(test_count) + "/" + str(len(test_list)) + " PASSED")
