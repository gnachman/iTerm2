#!/usr/bin/python

import itertools

def get_ranges(i):
    for a, b in itertools.groupby(enumerate(i), lambda (x, y): y - x):
        b = list(b)
        yield b[0][1], b[-1][1]

contents = []
while True:
    try:
        line = raw_input("").split(" ")
    except EOFError:
        break
    contents.append(line)

for tuple in contents:
  min = int(tuple[0], 16)
  max = int(tuple[1], 16)
  print "[set addCharactersInRange:NSMakeRange(%s, %s)];" % (hex(min), str(max - min + 1))
