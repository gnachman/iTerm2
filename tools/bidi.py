#!/usr/bin/env python3
import itertools
import os
import requests

UCD_BASE_URL = "https://unicode.org/Public/UCD/latest/ucd/"
FILES = ["UnicodeData.txt"]

def download_file(url, filename):
    """
    Download a file from a given URL and save it locally.
    """
    if os.path.exists(filename):
        return
    response = requests.get(url)
    response.raise_for_status()
    with open(filename, "wb") as file:
        file.write(response.content)

def find_strong_ltr_codes():
    """
    Load bidi classes from UnicodeData.txt.
    """
    bidi_classes = set([
        "L"])
    codes = {}

    with open("UnicodeData.txt", "r", encoding="utf-8") as file:
        for line in file:
            fields = line.strip().split(";")
            if len(fields) < 5:
                continue  # Skip malformed lines
            code_point = int(fields[0], 16)
            bidi_class = fields[4]
            if bidi_class in bidi_classes:
                codes[code_point] = fields[1]

    return codes

def find_strong_rtl_codes():
    """
    Load bidi classes from UnicodeData.txt.
    """
    bidi_classes = set([
        "R",
        "AL"])
    codes = {}

    with open("UnicodeData.txt", "r", encoding="utf-8") as file:
        for line in file:
            fields = line.strip().split(";")
            if len(fields) < 5:
                continue  # Skip malformed lines
            code_point = int(fields[0], 16)
            bidi_class = fields[4]
            if bidi_class in bidi_classes:
                codes[code_point] = fields[1]

    return codes


def find_bidi_codes():
    """
    Load bidi classes from UnicodeData.txt.
    """
    bidi_classes = set([
        "R",
        "AL",
        "AN",
        "RLE",
        "RLO",
        "RLI",
        "FSI",
        "PDF",
        "PDI",
        "LRE",
        "LRO",
        "LRI"])
    codes = {}

    with open("UnicodeData.txt", "r", encoding="utf-8") as file:
        for line in file:
            fields = line.strip().split(";")
            if len(fields) < 5:
                continue  # Skip malformed lines
            code_point = int(fields[0], 16)
            bidi_class = fields[4]
            if bidi_class in bidi_classes:
                codes[code_point] = fields[1]

    return codes

def get_bidi_codes():
    """
    Fetch UnicodeData.txt and process it to output a list of sorted code points
    that are strong RTL or weak RTL.
    """
    # Download necessary files
    for filename in FILES:
        download_file(UCD_BASE_URL + filename, filename)

    # Load strong and weak RTL code points
    return find_bidi_codes()

def get_strong_rtl_codes():
    # Download necessary files
    for filename in FILES:
        download_file(UCD_BASE_URL + filename, filename)

    # Load strong and weak RTL code points
    return find_strong_rtl_codes()

def get_strong_ltr_codes():
    # Download necessary files
    for filename in FILES:
        download_file(UCD_BASE_URL + filename, filename)

    # Load strong and weak ltr code points
    return find_strong_ltr_codes()

def get_strong_ltr_codes():
    # Download necessary files
    for filename in FILES:
        download_file(UCD_BASE_URL + filename, filename)

    # Load strong and weak LTR code points
    return find_strong_ltr_codes()

def get_ranges(i):
    def difference(pair):
        x, y = pair
        return y - x
    for a, b in itertools.groupby(enumerate(i), difference):
        b = list(b)
        yield b[0][1], b[-1][1]

def output(name, label, variable, codes):
    print("// " + label)
    print("// Run tools/bidi.py to generate this")
    print(f"+ (NSCharacterSet *){name} " + "{")
    print("    static dispatch_once_t onceToken;")
    print("    static NSCharacterSet *characterSet;")
    print("    dispatch_once(&onceToken, ^{")
    print("        NSMutableCharacterSet *mutableCharacterSet = [[NSMutableCharacterSet alloc] init];")

    for r in get_ranges(codes.keys()):
        start = r[0]
        count = r[1] - r[0] + 1
        if count == 1:
            comment = codes[start]
        else:
            comment = f'{codes[start]}...{codes[start+count-1]}'
        print("        [%s addCharactersInRange:NSMakeRange(%s, %d)];  // %s" % (variable, hex(start), count, comment))
    print("")
    print("        characterSet = mutableCharacterSet;")
    print("    });")
    print("    return characterSet;")
    print("}")

def print_rtlSmellingCodePoints():
    # Output the RTL code points
    output("rtlSmellingCodePoints", "Strong RTL and weak RTL code points", "mutableCharacterSet", get_bidi_codes())

def print_strongCodePoints():
    # Output strong RTL/LTR code points
    output("strongRTLCodePoints", "Strong RTL code points", "mutableCharacterSet", get_strong_rtl_codes())
    output("strongLTRCodePoints", "Strong LTR code points", "mutableCharacterSet", get_strong_ltr_codes())

print_rtlSmellingCodePoints()
print("")
print_strongCodePoints()

