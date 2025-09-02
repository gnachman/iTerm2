#!/usr/bin/python3

import itertools

def get_ranges(i):
    def difference(pair):
        x, y = pair
        return y - x
    for a, b in itertools.groupby(enumerate(i), difference):
        b = list(b)
        yield b[0][1], b[-1][1]

contents = []
while True:
    try:
        line = input()
    except EOFError:
        break
    contents.append(line)

numbers = map(lambda x: int(x, 16), contents)
for x in get_ranges(numbers):
  print("[set addCharactersInRange:NSMakeRange(%s, %s)];" % (hex(x[0]), str(x[1] - x[0] + 1)))
