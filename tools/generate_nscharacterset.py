#!/usr/bin/env python3
"""
Generate NSCharacterSet+iTerm.m from Unicode data files.

This script downloads necessary Unicode data files and generates the
NSCharacterSet+iTerm.m file with up-to-date character set definitions.

Data sources:
- UnicodeData.txt: Basic character properties (bidi classes, general categories)
- DerivedCoreProperties.txt: Derived properties like Grapheme_Base, Default_Ignorable_Code_Point
- emoji-data.txt: Emoji properties (Emoji, Emoji_Presentation)
- emoji-sequences.txt: Emoji sequences (for VS16 detection)
- idn-chars.txt: IDN characters for URL detection

Usage:
    python3 tools/generate_nscharacterset.py

Output:
    sources/Categories/NSCharacterSet+iTerm.m
    sources/CharacterSets/iTermCharacterSets.m
"""

import itertools
import os
import re
import sys
import urllib.request
import ssl
from pathlib import Path

# URLs for Unicode data files
UNICODE_DATA_URL = "https://unicode.org/Public/UCD/latest/ucd/UnicodeData.txt"
DERIVED_CORE_PROPS_URL = "https://unicode.org/Public/UCD/latest/ucd/DerivedCoreProperties.txt"
EMOJI_DATA_URL = "https://unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt"
EMOJI_SEQUENCES_URL = "https://unicode.org/Public/emoji/latest/emoji-sequences.txt"
IDN_CHARS_URL = "https://unicode.org/reports/tr36/idn-chars.txt"

# Cache directory for downloaded files
CACHE_DIR = Path(__file__).parent / ".unicode_cache"


def fetch_url(url: str) -> str:
    """Fetch URL content with robust TLS handling."""
    def _open_with_context(ctx):
        if ctx is None:
            with urllib.request.urlopen(url, timeout=30) as resp:
                return resp.read().decode("utf-8", errors="replace")
        else:
            opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
            with opener.open(url, timeout=30) as resp:
                return resp.read().decode("utf-8", errors="replace")

    # Try with certifi first if available
    try:
        import certifi
        ctx = ssl.create_default_context(cafile=certifi.where())
        return _open_with_context(ctx)
    except ImportError:
        pass

    # Fall back to default context
    try:
        return _open_with_context(None)
    except ssl.SSLCertVerificationError:
        # Try unverified as last resort
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return _open_with_context(ctx)


def get_cached_or_fetch(url: str, filename: str) -> str:
    """Get file from cache or fetch from URL."""
    CACHE_DIR.mkdir(exist_ok=True)
    cache_path = CACHE_DIR / filename

    if cache_path.exists():
        print(f"  Using cached {filename}")
        return cache_path.read_text(encoding="utf-8", errors="replace")

    print(f"  Downloading {filename}...")
    content = fetch_url(url)
    cache_path.write_text(content, encoding="utf-8")
    return content


def get_ranges(nums):
    """Convert a sorted list of numbers into (start, end) ranges."""
    if not nums:
        return
    nums = sorted(set(nums))
    for _, group in itertools.groupby(enumerate(nums), lambda t: t[1] - t[0]):
        g = list(group)
        yield g[0][1], g[-1][1]


def format_ranges(nums, variable: str, indent: str = "        ") -> list[str]:
    """Format number ranges as Objective-C addCharactersInRange calls."""
    lines = []
    for start, end in get_ranges(nums):
        count = end - start + 1
        lines.append(f"{indent}[{variable} addCharactersInRange:NSMakeRange({hex(start)}, {count})];")
    return lines


def format_ranges_with_comments(nums_with_names: dict, variable: str, indent: str = "        ") -> list[str]:
    """Format number ranges with comments showing character names."""
    lines = []
    nums = sorted(nums_with_names.keys())
    for start, end in get_ranges(nums):
        count = end - start + 1
        if count == 1:
            comment = nums_with_names.get(start, "")
        else:
            start_name = nums_with_names.get(start, "")
            end_name = nums_with_names.get(end, "")
            comment = f"{start_name}...{end_name}"
        lines.append(f"{indent}[{variable} addCharactersInRange:NSMakeRange({hex(start)}, {count})];  // {comment}")
    return lines


# ============================================================================
# C code formatters (for iTermCharacterSets.c)
# ============================================================================

def split_bmp_supp(code_points):
    """Split code points into BMP (< 0x10000) and supplementary (>= 0x10000)."""
    bmp = [cp for cp in code_points if cp < 0x10000]
    supp = [cp for cp in code_points if cp >= 0x10000]
    return sorted(set(bmp)), sorted(set(supp))


def format_c_bmp_init(nums, bitmap_name, indent="        "):
    """Format code points as C setRange calls for BMP bitmap initialization."""
    lines = []
    for start, end in get_ranges(nums):
        count = end - start + 1
        lines.append(f"{indent}setRange(&{bitmap_name}, {hex(start)}, {count});")
    return lines


def format_c_supp_ranges(nums, indent="    "):
    """Format supplementary code points as C CharRange array entries."""
    lines = []
    for start, end in get_ranges(nums):
        lines.append(f"{indent}{{{hex(start)}, {hex(end)}}},")
    return lines


# ============================================================================
# Parsers for Unicode data files
# ============================================================================

def parse_unicode_data(content: str) -> dict:
    """
    Parse UnicodeData.txt and return a dict with:
    - 'by_code': {code_point: {'name': str, 'gc': str, 'bidi': str}}
    """
    result = {}
    for line in content.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split(";")
        if len(fields) < 5:
            continue
        try:
            code = int(fields[0], 16)
            result[code] = {
                'name': fields[1],
                'gc': fields[2],
                'bidi': fields[4]
            }
        except ValueError:
            continue
    return result


def parse_derived_props(content: str, prop_name: str) -> set[int]:
    """Parse DerivedCoreProperties.txt for a specific property."""
    prop_re = re.compile(r"^\s*([0-9A-Fa-f]{4,6})(?:\.\.([0-9A-Fa-f]{4,6}))?\s*;\s*(\S+)")
    result = set()
    for line in content.splitlines():
        m = prop_re.match(line)
        if not m:
            continue
        start_s, end_s, name = m.groups()
        if name != prop_name:
            continue
        start = int(start_s, 16)
        end = start if end_s is None else int(end_s, 16)
        result.update(range(start, end + 1))
    return result


def parse_emoji_data(content: str, prop_name: str) -> set[int]:
    """Parse emoji-data.txt for a specific property."""
    result = set()
    for line in content.splitlines():
        # Remove comments
        if "#" in line:
            line = line[:line.index("#")]
        line = line.strip()
        if not line:
            continue

        parts = line.split(";")
        if len(parts) < 2:
            continue

        prop = parts[1].strip()
        if prop != prop_name:
            continue

        # Parse code point range
        range_part = parts[0].strip()
        if ".." in range_part:
            start_s, end_s = range_part.split("..")
            start = int(start_s, 16)
            end = int(end_s, 16)
            result.update(range(start, end + 1))
        else:
            result.add(int(range_part, 16))

    return result


def parse_emoji_sequences_vs16(content: str) -> set[int]:
    """Parse emoji-sequences.txt for emoji that accept VS16."""
    result = set()
    for line in content.splitlines():
        if line.startswith("#"):
            continue
        parts = line.split(";")
        if len(parts) < 1:
            continue
        sequences = parts[0].split()
        if len(sequences) >= 2 and sequences[1].upper() == "FE0F":
            try:
                code = int(sequences[0], 16)
                result.add(code)
            except ValueError:
                continue
    return result


def parse_idn_chars(content: str) -> list[int]:
    """Parse idn-chars.txt for IDN characters."""
    values = []
    category = None
    last_was_empty = False
    is_comment = False

    for line in content.splitlines():
        if len(line.strip()) == 0:
            last_was_empty = True
            continue

        is_comment = line.startswith("#")
        if last_was_empty and is_comment:
            category = line[1:].strip()
        last_was_empty = False

        if is_comment:
            continue

        if category in ["IDN-Deleted", "IDN-Illegal"]:
            continue

        # Remove comments
        if "#" in line:
            line = line[:line.index("#")]

        parts = line.split(";")
        if len(parts) == 0:
            continue

        parts = parts[0].strip().split("..")
        try:
            value = int(parts[0], 16)
        except (ValueError, IndexError):
            continue

        if len(parts) == 1:
            values.append(value)
        elif len(parts) == 2:
            count = int(parts[1], 16) - int(parts[0], 16) + 1
            for i in range(count):
                values.append(value + i)

    return values


# ============================================================================
# Character set generators
# ============================================================================

def generate_idn_characters(idn_content: str) -> list[str]:
    """Generate idnCharacters method."""
    values = parse_idn_chars(idn_content)
    return format_ranges(values, "set")


def generate_emoji_default_text_presentation(emoji_data_content: str) -> list[str]:
    """Generate emojiWithDefaultTextPresentation (Emoji - Emoji_Presentation)."""
    all_emoji = parse_emoji_data(emoji_data_content, "Emoji")
    emoji_presentation = parse_emoji_data(emoji_data_content, "Emoji_Presentation")
    text_presentation = sorted(all_emoji - emoji_presentation)
    return format_ranges(text_presentation, "textPresentation")


def generate_emoji_default_emoji_presentation(emoji_data_content: str) -> tuple[list[str], int]:
    """Generate emojiWithDefaultEmojiPresentation and return min code point."""
    emoji_presentation = parse_emoji_data(emoji_data_content, "Emoji_Presentation")
    if not emoji_presentation:
        raise ValueError("No Emoji_Presentation characters found - emoji-data.txt may be corrupt")
    codes = sorted(emoji_presentation)
    min_code = min(codes)
    return format_ranges(codes, "emojiPresentation"), min_code


def generate_strong_rtl_codes(unicode_data: dict) -> list[str]:
    """Generate strongRTLCodePoints method."""
    bidi_classes = {"R", "AL"}
    codes_with_names = {
        code: info['name']
        for code, info in unicode_data.items()
        if info['bidi'] in bidi_classes
    }
    return format_ranges_with_comments(codes_with_names, "mutableCharacterSet")


def generate_strong_ltr_codes(unicode_data: dict) -> list[str]:
    """Generate strongLTRCodePoints method."""
    codes_with_names = {
        code: info['name']
        for code, info in unicode_data.items()
        if info['bidi'] == "L"
    }
    return format_ranges_with_comments(codes_with_names, "mutableCharacterSet")


# ============================================================================
# Main generation
# ============================================================================

def main():
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    objc_template_path = script_dir / "NSCharacterSet+iTerm.m.template"
    objc_output_path = repo_root / "sources" / "Categories" / "NSCharacterSet+iTerm.m"
    c_template_path = script_dir / "iTermCharacterSets.m.template"
    c_output_path = repo_root / "sources" / "CharacterSets" / "iTermCharacterSets.m"

    print("Downloading Unicode data files...")
    unicode_data_content = get_cached_or_fetch(UNICODE_DATA_URL, "UnicodeData.txt")
    derived_props_content = get_cached_or_fetch(DERIVED_CORE_PROPS_URL, "DerivedCoreProperties.txt")
    emoji_data_content = get_cached_or_fetch(EMOJI_DATA_URL, "emoji-data.txt")
    emoji_sequences_content = get_cached_or_fetch(EMOJI_SEQUENCES_URL, "emoji-sequences.txt")
    idn_content = get_cached_or_fetch(IDN_CHARS_URL, "idn-chars.txt")

    print("Parsing Unicode data...")
    unicode_data = parse_unicode_data(unicode_data_content)

    print("Generating character sets...")

    # Generate Objective-C character sets (for NSCharacterSet+iTerm.m)
    idn_ranges = generate_idn_characters(idn_content)
    text_presentation_ranges = generate_emoji_default_text_presentation(emoji_data_content)
    emoji_presentation_ranges, min_emoji_code = generate_emoji_default_emoji_presentation(emoji_data_content)
    strong_rtl_ranges = generate_strong_rtl_codes(unicode_data)
    strong_ltr_ranges = generate_strong_ltr_codes(unicode_data)

    # ---- Generate NSCharacterSet+iTerm.m ----

    print("Reading ObjC template...")
    objc_template = objc_template_path.read_text(encoding="utf-8")

    print("Substituting ObjC values...")
    objc_replacements = {
        "{{IDN_RANGES}}": "\n".join(idn_ranges),
        "{{EMOJI_TEXT_PRESENTATION_RANGES}}": "\n".join(text_presentation_ranges),
        "{{EMOJI_PRESENTATION_RANGES}}": "\n".join(emoji_presentation_ranges),
        "{{STRONG_RTL_RANGES}}": "\n".join(strong_rtl_ranges),
        "{{STRONG_LTR_RANGES}}": "\n".join(strong_ltr_ranges),
        "{{MIN_EMOJI_PRESENTATION_CODE}}": hex(min_emoji_code),
    }

    objc_output = objc_template
    for placeholder, value in objc_replacements.items():
        objc_output = objc_output.replace(placeholder, value)

    print(f"Writing {objc_output_path}...")
    objc_output_path.write_text(objc_output, encoding="utf-8")

    # ---- Generate iTermCharacterSets.c ----

    print("Generating C character set data...")

    # Get raw code point sets for C generation
    ignorable_codes = sorted(
        parse_derived_props(derived_props_content, "Default_Ignorable_Code_Point") - {0x200b}
    )
    spacing_combining_codes = sorted(
        code for code, info in unicode_data.items() if info['gc'] == 'Mc'
    )

    vs16_emoji = parse_emoji_sequences_vs16(emoji_sequences_content)
    all_emoji = parse_emoji_data(emoji_data_content, "Emoji")
    emoji_presentation = parse_emoji_data(emoji_data_content, "Emoji_Presentation")
    emoji_vs16_codes = sorted(vs16_emoji | (all_emoji - emoji_presentation))

    bidi_classes = {"R", "AL", "AN", "RLE", "RLO", "RLI", "FSI", "PDF", "PDI", "LRE", "LRO", "LRI"}
    rtl_codes = sorted(
        code for code, info in unicode_data.items() if info['bidi'] in bidi_classes
    )

    # codePointsWithOwnCell = baseCharacters + spacingCombiningMarks + modifierLetters
    # baseCharacters = Grapheme_Base - Default_Ignorable_Code_Point
    grapheme_base = parse_derived_props(derived_props_content, "Grapheme_Base")
    default_ignorable = parse_derived_props(derived_props_content, "Default_Ignorable_Code_Point")
    base_codes = grapheme_base - default_ignorable
    modifier_letter_codes = set(
        code for code, info in unicode_data.items() if info['gc'] == 'Lm'
    )
    own_cell_codes = sorted(base_codes | set(spacing_combining_codes) | modifier_letter_codes)

    # Split into BMP and supplementary for each set
    ignorable_bmp, ignorable_supp = split_bmp_supp(ignorable_codes)
    scm_bmp, scm_supp = split_bmp_supp(spacing_combining_codes)
    vs16_bmp, vs16_supp = split_bmp_supp(emoji_vs16_codes)
    rtl_bmp, rtl_supp = split_bmp_supp(rtl_codes)
    own_cell_bmp, own_cell_supp = split_bmp_supp(own_cell_codes)

    print("Reading C template...")
    c_template = c_template_path.read_text(encoding="utf-8")

    print("Substituting C values...")
    c_replacements = {
        "{{IGNORABLE_SUPP_RANGES}}": "\n".join(format_c_supp_ranges(ignorable_supp)),
        "{{SPACING_COMBINING_MARKS_SUPP_RANGES}}": "\n".join(format_c_supp_ranges(scm_supp)),
        "{{EMOJI_VS16_SUPP_RANGES}}": "\n".join(format_c_supp_ranges(vs16_supp)),
        "{{RTL_SUPP_RANGES}}": "\n".join(format_c_supp_ranges(rtl_supp)),
        "{{CODE_POINTS_WITH_OWN_CELL_SUPP_RANGES}}": "\n".join(format_c_supp_ranges(own_cell_supp)),
        "{{IGNORABLE_BMP_INIT}}": "\n".join(format_c_bmp_init(ignorable_bmp, "sIgnorableBMP")),
        "{{SPACING_COMBINING_MARKS_BMP_INIT}}": "\n".join(format_c_bmp_init(scm_bmp, "sSpacingCombiningMarksBMP")),
        "{{EMOJI_VS16_BMP_INIT}}": "\n".join(format_c_bmp_init(vs16_bmp, "sEmojiAcceptingVS16BMP")),
        "{{RTL_BMP_INIT}}": "\n".join(format_c_bmp_init(rtl_bmp, "sRTLBMP")),
        "{{CODE_POINTS_WITH_OWN_CELL_BMP_INIT}}": "\n".join(format_c_bmp_init(own_cell_bmp, "sCodePointsWithOwnCellBMP")),
    }

    c_output = c_template
    for placeholder, value in c_replacements.items():
        c_output = c_output.replace(placeholder, value)

    print(f"Writing {c_output_path}...")
    c_output_path.write_text(c_output, encoding="utf-8")

    print("Done!")
    print(f"\nTo refresh the cache, delete: {CACHE_DIR}")


if __name__ == "__main__":
    main()
