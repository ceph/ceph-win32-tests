#!/usr/bin/python

import sys
import re

def strip_comments(line):
    return re.sub(" *# .*", "", line)


def is_test_class_name(line):
    return re.match(r"[^ ].*\.", line)


for line in sys.stdin:
    line = strip_comments(line).strip()

    if is_test_class_name(line):
        test_class_name = line.strip(".")
    else:
        test_name = line
        print("%s.%s" % (test_class_name, test_name))
