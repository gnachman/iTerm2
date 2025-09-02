#!/usr/bin/env python3
import requests
import itertools

def download_file(url, filename):
    """
    Download a file from a given URL and save it locally.
    """
    response = requests.get(url)
    with open(filename, "wb") as file:
        file.write(response.content)

def get_ranges(i):
    for a, b in itertools.groupby(enumerate(i), lambda (x, y): y - x):
        b = list(b)
        yield b[0][1], b[-1][1]

def read_lines():
    contents = []
    while True:
        try:
            line = raw_input("")
        except EOFError:
            break
        contents.append(line)
    return contents

def read_fields():
    contents = []
    while True:
        try:
            line = raw_input("").split(" ")
        except EOFError:
            break
        contents.append(line)
    return contents

def range_to_range(contents):
    for tuple in contents:
        min = int(tuple[0], 16)
        max = int(tuple[1], 16)
        print "[set addCharactersInRange:NSMakeRange(%s, %s)];" % (hex(min), str(max - min + 1))

def list_to_range(contents):
    numbers = map(lambda x: int(x, 16), contents)
    for x in get_ranges(numbers):
        print "[set addCharactersInRange:NSMakeRange(%s, %s)];" % (hex(x[0]), str(x[1] - x[0] + 1))

download_file('https://unicode.org/reports/tr36/idn-chars.txt', 'idn-chars.txt')

