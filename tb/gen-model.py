#!/usr/bin/env python3

import json
import argparse
import random

parser = argparse.ArgumentParser()
parser.add_argument("-o", "--output", metavar="<filename>", default=None, help="Output JSON file")
parser.add_argument("-e", "--extract", metavar="<filename>.sv", help="Extract parameters from a SystemVerilog top-level module file and generate a JSON parameters spec file from it")
parser.add_argument("-g", "--generate", metavar="<filename>.json", help="Generate json file with randomized parameters from a json parameter spec file")
parser.add_argument("-v", "--verilator", metavar="<filename>.json", help="Convert json file with randomized parameters to a string containing parameter override arguments to be used in the Verilator command-line")
args = parser.parse_args()

def check_constraints(val, constraints, rand_dict):
    for c in constraints:
        if not c['function'](val, rand_dict[c['parameter_dep']]):
            return False
    return True

if args.extract:
    d = {}

    with open(args.extract, "r") as f:
        for line in f:
            s = line.split()
            if len(s) < 4:
                continue
            if s[0] == "parameter":
                # For lines that start with parameter, create a dictionary containing a key called "range" which
                # will essentially hold an array of just 1 value which is also taken from the SV file
                d[s[1].lstrip().rstrip()] = {"range": [int(s[3].lstrip().rstrip().strip(","))]}

    # Write to console or file
    if args.output:
        with open(args.output, "w") as o:
            json.dump(d, o, indent = 4)
    else:
        print(json.dumps(d, indent = 4))

    exit(0)

if args.generate:
    rand_dict = {}
    param_dict = {}

    # Load the parameter spec file
    with open(args.generate, "r") as param_spec:
        param_dict = json.load(param_spec)

    random.seed()

    # Generate a random value within the acceptable range of values for each parameter
    for param, d in param_dict.items():
        # The range key can have a list or a string specifying a range or even list comprehension code
        d['range'] = d['range'] if type(d['range']) is list else eval(d['range'])
        rand_dict[param] = random.choice(d['range'])

    # Check any constraints
    for param, d in param_dict.items():
        # The function key contains a string with a lambda definition, eval it
        constraints = [{k: eval(v) if k == 'function' and type(v) is str else v for k,v in c.items()} for c in d['constraints']] if 'constraints' in d else []
        while check_constraints(rand_dict[param], constraints, rand_dict) is False:
            rand_dict[param] = random.choice(d['range'])

    # Write to console or file
    if args.output:
        with open(args.output, "w") as o:
            json.dump(rand_dict, o, indent = 4)
    else:
        print(json.dumps(rand_dict, indent = 4))

    exit(0)

if args.verilator:
    s = ""

    # Just go through the dictionary of parameter values and create the Verilator command-line arguments
    with open(args.verilator, "r") as j:
        rand_dict = json.load(j)
        for param, val in rand_dict.items():
            s += "-G" + str(param) + "=" + str(val) + " "

    print(s)
    exit(0)

parser.print_usage()
