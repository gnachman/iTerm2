#!/usr/bin/env python3
import itertools
import requests

def get_ranges(i):
    def difference(pair):
        x, y = pair
        return y - x
    for a, b in itertools.groupby(enumerate(i), difference):
        b = list(b)
        yield b[0][1], b[-1][1]

def parse(s):
    parts = s.split("..")
    if len(parts) == 1:
        return (int(parts[0], 16), 1)
    low = int(parts[0], 16)
    high = int(parts[1], 16)
    return (low, high - low + 1)

def output(label, variable, values):
    print("// " + label)
    nums = []
    for v in values:
        start, count = parse(v)
        for i in range(count):
            nums.append(start + i)
    for r in get_ranges(nums):
        start = r[0]
        count = r[1] - r[0] + 1
        print("        [%s addCharactersInRange:NSMakeRange(%s, %d)];" % (variable, hex(start), count))
    print("")

def output_sequences():
    """Output emoji that accept VS16"""
    f = open("emoji-sequences.txt", "r")
    ranges = []
    for line in f:
        if line.startswith("#"):
            continue
        parts = line.split(";")
        if len(parts) < 1:
            continue
        sequences = parts[0].split(" ")
        if len(sequences) < 2:
            continue
        if sequences[1] == "FE0F":
            ranges.append(sequences[0])


    output("Emoji", "emoji", ranges)

def download_file(url, filename):
    """
    Download a file from a given URL and save it locally.
    """
    response = requests.get(url)
    with open(filename, "wb") as file:
        file.write(response.content)

def output_default_emoji_presentation():
    """Output emoji that have a default emoji presentation."""
    # https://unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt
    download_file("https://unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt", "emoji-data.txt")
    f = open("emoji-data.txt", "r")
    ranges = []
    for line in f:
        try:
            i = line.index("#")
            line = line[0:i]
        except:
            pass
        parts = line.split(";")
        if len(parts) < 2:
            continue
        flavor = parts[1].strip()
        if flavor != "Emoji_Presentation":
            continue
        ranges.append(parts[0])
    output("EmojiPresentation", "emojiPresentation", ranges)

def get_all_emoji():
    """Returns the set of emoji base character."""
    # https://unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt
    f = open("emoji-data.txt", "r")
    emoji = []
    for line in f:
        try:
            i = line.index("#")
            line = line[0:i]
        except:
            pass
        parts = line.split(";")
        if len(parts) < 2:
            continue
        flavor = parts[1].strip()
        if flavor != "Emoji":
            continue
        minmax = parse(parts[0])
        for i in range(minmax[0], minmax[0] + minmax[1]):
            emoji.append(i)
    return set(emoji)

def output_default_text_presentation():
    """See issue 9185. Outputs default-text emoji that get emoji presentation
    when following a default-emoji presentation character."""
    # https://unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt
    emoji = list(get_all_emoji())
    download_file("https://unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt", "emoji-data.txt")
    f = open("emoji-data.txt", "r")
    for line in f:
        try:
            i = line.index("#")
            line = line[0:i]
        except:
            pass
        parts = line.split(";")
        if len(parts) < 2:
            continue
        flavor = parts[1].strip()
        if flavor != "Emoji_Presentation":
            continue
        minmax = parse(parts[0])
        for i in range(minmax[0], minmax[0] + minmax[1]):
            emoji.remove(i)

    emoji.sort()
    ranges = list(map(lambda x: format(x, 'x'), emoji))
    output("TextPresentation", "textPresentation", ranges)

def print_sequences_issue9185():
    # https://unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt
    emoji = list(get_all_emoji())
    f = open("emoji-data.txt", "r")
    for line in f:
        try:
            i = line.index("#")
            line = line[0:i]
        except:
            pass
        parts = line.split(";")
        if len(parts) < 2:
            continue
        flavor = parts[1].strip()
        if flavor != "Emoji_Presentation":
            continue
        minmax = parse(parts[0])
        for i in range(minmax[0], minmax[0] + minmax[1]):
            emoji.remove(i)

    emoji.sort()
    for i in emoji:
        print(f'{hex(i)}: \U0001f37b{chr(i)} regular={chr(i)} emojified={chr(i)+chr(0xfe0f)}')

# Uncomment the one you want:
#output_default_emoji_presentation()
#print_sequences_issue9185()
#output_upgradable_presentation()
output_default_text_presentation()
