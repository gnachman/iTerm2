#!/usr/bin/env python3
import binascii
import fileinput

for line in fileinput.input():
    line = line.rstrip()
    words = line.split()
    hexen = []
    for word in words:
        c = chr(int(word, 16)).encode('utf-8')
        hexbytes = binascii.hexlify(c, sep=' ')
        hex = hexbytes.decode('utf-8')
        hexen.append(hex)
    print(f"{line} -> {' '.join(hexen)}")
