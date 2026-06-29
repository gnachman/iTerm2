#!/usr/bin/env python3
# This program downloads Unicode data and updates iTermCharacterWidth.c in place.
#
# Usage: python3 tools/eastasian.py [unicode_version]
#
# Examples:
#   python3 tools/eastasian.py          # Use latest Unicode version
#   python3 tools/eastasian.py 16.0.0   # Use Unicode 16.0.0
#
# Note that ambiguous characters are unlikely ever to change again, while new
# emoji cause the full-width set to change every year.
#
# See also emoji.py for generators for other code.
import itertools
import os
import re
import sys
import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE_FILE = os.path.join(SCRIPT_DIR, "../sources/CharacterSets/iTermCharacterWidth.c")

# Default to latest, or specify version like "16.0.0"
UNICODE_VERSION = sys.argv[1] if len(sys.argv) > 1 else "latest"

def get_ranges(i):
    """Convert a list of individual code points to a list of (start, end) ranges."""
    def difference(pair):
        x, y = pair
        return y - x
    for a, b in itertools.groupby(enumerate(i), difference):
        b = list(b)
        yield b[0][1], b[-1][1]

def parse(s):
    """Parse a unicode range like '1F600..1F64F' or '1F600' into (start, count)."""
    parts = s.split("..")
    if len(parts) == 1:
        return (int(parts[0], 16), 1)
    low = int(parts[0], 16)
    high = int(parts[1], 16)
    return (low, high - low + 1)

def collect_ranges(values):
    """Convert parsed values into consolidated ranges as (start, end) tuples."""
    nums = []
    for v in values:
        start, count = parse(v)
        for i in range(count):
            nums.append(start + i)
    nums.sort()
    return list(get_ranges(nums))

def generate_supp_ranges(var_name, ranges, unicode_version):
    """Generate C code for supplementary plane range arrays."""
    supp_ranges = [(s, e) for s, e in ranges if e >= 0x10000]

    # Adjust start for ranges that span BMP and supplementary
    adjusted = []
    for s, e in supp_ranges:
        if s < 0x10000:
            s = 0x10000
        adjusted.append((s, e))

    lines = []
    lines.append(f"// Generated from Unicode {unicode_version} by tools/eastasian.py")
    lines.append(f"static const CharRange {var_name}[] = {{")
    for s, e in adjusted:
        lines.append(f"    {{{hex(s)}, {hex(e)}}},")
    lines.append("};")
    lines.append(f"static const int {var_name}Count = sizeof({var_name}) / sizeof({var_name}[0]);")
    return "\n".join(lines)

def generate_bmp_init(func_name, bitmap_var, ranges, unicode_version):
    """Generate C code for BMP bitmap initialization function."""
    lines = []
    lines.append(f"// Generated from Unicode {unicode_version} by tools/eastasian.py")
    lines.append(f"static void {func_name}(void) {{")
    lines.append(f"    memset(&{bitmap_var}, 0, sizeof({bitmap_var}));")
    lines.append("")

    for start, end in ranges:
        if start >= 0x10000:
            continue
        end = min(end, 0xffff)
        # Use setBit for single values, setBitRange for ranges
        if start == end:
            lines.append(f"    setBit(&{bitmap_var}, {hex(start)});")
        else:
            lines.append(f"    setBitRange(&{bitmap_var}, {hex(start)}, {hex(end)});")

    lines.append("}")
    return "\n".join(lines)

def download_file(url, filename):
    """Download a file from a given URL and save it locally."""
    print(f"Downloading {url}...")
    response = requests.get(url)
    with open(filename, "wb") as file:
        file.write(response.content)

def replace_array(content, array_name, replacement):
    """Replace a CharRange array and its count variable, including any preceding comment."""
    # Match optional comment line, then: static const CharRange name[] = { ... }; static const int nameCount = ...;
    pattern = (
        rf"(// Generated from Unicode [^\n]*\n)?"
        rf"static const CharRange {array_name}\[\] = \{{\n"
        rf"(.*?)"
        rf"\}};\n"
        rf"static const int {array_name}Count = [^;]+;"
    )
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        raise ValueError(f"Could not find array: {array_name}")
    return content[:match.start()] + replacement + content[match.end():]

def replace_function(content, func_name, replacement):
    """Replace a function definition, including any preceding comment."""
    # First try to match with a preceding comment
    start_pattern_with_comment = rf"// Generated from Unicode [^\n]*\nstatic void {func_name}\(void\) \{{"
    match = re.search(start_pattern_with_comment, content)

    if not match:
        # Fall back to matching without comment
        start_pattern = rf"static void {func_name}\(void\) \{{"
        match = re.search(start_pattern, content)

    if not match:
        raise ValueError(f"Could not find function: {func_name}")

    start = match.start()
    # Find matching closing brace by counting braces
    brace_count = 0
    i = match.end() - 1  # Start at the opening brace
    while i < len(content):
        if content[i] == '{':
            brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                end = i + 1
                break
        i += 1
    else:
        raise ValueError(f"Could not find end of function: {func_name}")

    return content[:start] + replacement + content[end:]

def main():
    # Build URLs based on version
    if UNICODE_VERSION == "latest":
        eaw_url = "https://unicode.org/Public/UNIDATA/EastAsianWidth.txt"
        emoji_url = "https://unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt"
    else:
        eaw_url = f"https://unicode.org/Public/{UNICODE_VERSION}/ucd/EastAsianWidth.txt"
        emoji_url = f"https://unicode.org/Public/{UNICODE_VERSION}/ucd/emoji/emoji-data.txt"

    # Download Unicode data files
    print(f"Using Unicode version: {UNICODE_VERSION}")
    download_file(eaw_url, "/tmp/EastAsianWidth.txt")
    download_file(emoji_url, "/tmp/emoji-data.txt")

    # Read the version from the downloaded file
    with open("/tmp/EastAsianWidth.txt", "r") as f:
        first_line = f.readline().strip()
        print(f"Downloaded: {first_line}")

    # Extract version string (e.g., "16.0.0" from "# EastAsianWidth-16.0.0.txt")
    import re as re_module
    version_match = re_module.search(r'EastAsianWidth-(\d+\.\d+\.\d+)\.txt', first_line)
    unicode_version_str = version_match.group(1) if version_match else UNICODE_VERSION

    # Parse EastAsianWidth.txt
    wide = []
    ambiguous = []
    with open("/tmp/EastAsianWidth.txt", "r") as f:
        for line in f:
            if line.startswith("#"):
                continue
            parts = line.split(";")
            if len(parts) < 2:
                continue
            prop = parts[1].strip()
            if prop.startswith("F ") or prop.startswith("W "):
                wide.append(parts[0])
            elif prop.startswith("A "):
                ambiguous.append(parts[0])

    # Collect ranges
    wide_ranges = collect_ranges(wide)
    ambiguous_ranges = collect_ranges(ambiguous)

    print(f"Found {len(wide_ranges)} full-width ranges")
    print(f"Found {len(ambiguous_ranges)} ambiguous-width ranges")

    # Read existing source file
    with open(SOURCE_FILE, "r") as f:
        content = f.read()

    # Generate new code sections
    new_fullwidth_supp = generate_supp_ranges("sFullWidthSupp9", wide_ranges, unicode_version_str)
    new_ambiguous_supp = generate_supp_ranges("sAmbiguousSupp9", ambiguous_ranges, unicode_version_str)
    new_fullwidth_init = generate_bmp_init("initFullWidth9", "sFullWidthBMP9", wide_ranges, unicode_version_str)
    new_ambiguous_init = generate_bmp_init("initAmbiguous9", "sAmbiguousBMP9", ambiguous_ranges, unicode_version_str)

    # Replace arrays and functions
    content = replace_array(content, "sFullWidthSupp9", new_fullwidth_supp)
    content = replace_array(content, "sAmbiguousSupp9", new_ambiguous_supp)
    content = replace_function(content, "initFullWidth9", new_fullwidth_init)
    content = replace_function(content, "initAmbiguous9", new_ambiguous_init)

    # Write updated file
    with open(SOURCE_FILE, "w") as f:
        f.write(content)

    print(f"Updated {SOURCE_FILE}")
    print(f"  Full-width: {len([r for r in wide_ranges if r[0] < 0x10000])} BMP ranges, "
          f"{len([r for r in wide_ranges if r[1] >= 0x10000])} supplementary ranges")
    print(f"  Ambiguous: {len([r for r in ambiguous_ranges if r[0] < 0x10000])} BMP ranges, "
          f"{len([r for r in ambiguous_ranges if r[1] >= 0x10000])} supplementary ranges")

if __name__ == "__main__":
    main()
