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
    sources/NSCharacterSet+iTerm.m
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


def generate_base_characters(derived_props_content: str) -> list[str]:
    """Generate baseCharactersForUnicodeVersion method (Grapheme_Base - Default_Ignorable)."""
    grapheme_base = parse_derived_props(derived_props_content, "Grapheme_Base")
    ignorable = parse_derived_props(derived_props_content, "Default_Ignorable_Code_Point")
    codes = sorted(grapheme_base - ignorable)
    return format_ranges(codes, "set")


def generate_spacing_combining_marks(unicode_data: dict) -> list[str]:
    """Generate spacingCombiningMarksForUnicodeVersion method (gc=Mc)."""
    codes = [code for code, info in unicode_data.items() if info['gc'] == 'Mc']
    return format_ranges(codes, "set")


def generate_modifier_letters(unicode_data: dict) -> list[str]:
    """Generate modifierLettersForUnicodeVersion method (gc=Lm)."""
    codes = [code for code, info in unicode_data.items() if info['gc'] == 'Lm']
    return format_ranges(codes, "set")


def generate_ignorable_characters(derived_props_content: str) -> list[str]:
    """Generate ignorableCharactersForUnicodeVersion method."""
    ignorable = parse_derived_props(derived_props_content, "Default_Ignorable_Code_Point")
    # Remove 0x200b as it's handled specially at runtime
    ignorable.discard(0x200b)
    return format_ranges(ignorable, "defaultIgnorables")


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


def generate_emoji_accepting_vs16(emoji_sequences_content: str, emoji_data_content: str) -> list[str]:
    """Generate emojiAcceptingVS16 method."""
    # Get emoji that have FE0F in sequences
    vs16_emoji = parse_emoji_sequences_vs16(emoji_sequences_content)

    # Also get emoji with default text presentation (they all accept VS16)
    all_emoji = parse_emoji_data(emoji_data_content, "Emoji")
    emoji_presentation = parse_emoji_data(emoji_data_content, "Emoji_Presentation")
    text_presentation = all_emoji - emoji_presentation

    # Combine both sets
    combined = vs16_emoji | text_presentation
    return format_ranges(sorted(combined), "emoji")


def generate_rtl_smelling_codes(unicode_data: dict) -> list[str]:
    """Generate rtlSmellingCodePoints method."""
    bidi_classes = {"R", "AL", "AN", "RLE", "RLO", "RLI", "FSI", "PDF", "PDI", "LRE", "LRO", "LRI"}
    codes_with_names = {
        code: info['name']
        for code, info in unicode_data.items()
        if info['bidi'] in bidi_classes
    }
    return format_ranges_with_comments(codes_with_names, "mutableCharacterSet")


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
    template_path = script_dir / "NSCharacterSet+iTerm.m.template"
    output_path = repo_root / "sources" / "NSCharacterSet+iTerm.m"

    print("Downloading Unicode data files...")
    unicode_data_content = get_cached_or_fetch(UNICODE_DATA_URL, "UnicodeData.txt")
    derived_props_content = get_cached_or_fetch(DERIVED_CORE_PROPS_URL, "DerivedCoreProperties.txt")
    emoji_data_content = get_cached_or_fetch(EMOJI_DATA_URL, "emoji-data.txt")
    emoji_sequences_content = get_cached_or_fetch(EMOJI_SEQUENCES_URL, "emoji-sequences.txt")
    idn_content = get_cached_or_fetch(IDN_CHARS_URL, "idn-chars.txt")

    print("Parsing Unicode data...")
    unicode_data = parse_unicode_data(unicode_data_content)

    print("Generating character sets...")

    # Generate all character sets
    idn_ranges = generate_idn_characters(idn_content)
    base_ranges = generate_base_characters(derived_props_content)
    spacing_combining_ranges = generate_spacing_combining_marks(unicode_data)
    modifier_letter_ranges = generate_modifier_letters(unicode_data)
    ignorable_ranges = generate_ignorable_characters(derived_props_content)
    text_presentation_ranges = generate_emoji_default_text_presentation(emoji_data_content)
    emoji_presentation_ranges, min_emoji_code = generate_emoji_default_emoji_presentation(emoji_data_content)
    vs16_ranges = generate_emoji_accepting_vs16(emoji_sequences_content, emoji_data_content)
    rtl_smelling_ranges = generate_rtl_smelling_codes(unicode_data)
    strong_rtl_ranges = generate_strong_rtl_codes(unicode_data)
    strong_ltr_ranges = generate_strong_ltr_codes(unicode_data)

    print("Reading template...")
    template = template_path.read_text(encoding="utf-8")

    print("Substituting values...")
    replacements = {
        "{{IDN_RANGES}}": "\n".join(idn_ranges),
        "{{BASE_CHARACTER_RANGES}}": "\n".join(base_ranges),
        "{{SPACING_COMBINING_MARK_RANGES}}": "\n".join(spacing_combining_ranges),
        "{{MODIFIER_LETTER_RANGES}}": "\n".join(modifier_letter_ranges),
        "{{IGNORABLE_CHARACTER_RANGES}}": "\n".join(ignorable_ranges),
        "{{EMOJI_TEXT_PRESENTATION_RANGES}}": "\n".join(text_presentation_ranges),
        "{{EMOJI_PRESENTATION_RANGES}}": "\n".join(emoji_presentation_ranges),
        "{{EMOJI_VS16_RANGES}}": "\n".join(vs16_ranges),
        "{{RTL_SMELLING_RANGES}}": "\n".join(rtl_smelling_ranges),
        "{{STRONG_RTL_RANGES}}": "\n".join(strong_rtl_ranges),
        "{{STRONG_LTR_RANGES}}": "\n".join(strong_ltr_ranges),
        "{{MIN_EMOJI_PRESENTATION_CODE}}": hex(min_emoji_code),
    }

    output = template
    for placeholder, value in replacements.items():
        output = output.replace(placeholder, value)

    print(f"Writing {output_path}...")
    output_path.write_text(output, encoding="utf-8")

    print("Done!")
    print(f"\nTo refresh the cache, delete: {CACHE_DIR}")


if __name__ == "__main__":
    main()
