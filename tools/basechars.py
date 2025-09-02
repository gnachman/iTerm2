#!/usr/bin/env python3
import csv
import io
import re
import sys
import urllib.request
from itertools import groupby
import os
import ssl
import urllib.request

TIMEOUT = 30

def fetch(url: str, *, use_certifi_first: bool = True) -> str:
    """
    Fetch URL text with robust TLS handling on macOS Framework Pythons.

    Strategy:
      - If certifi is available, build an SSL context with its CA bundle.
      - Otherwise, try the default SSL context.
      - If default fails with CERTIFICATE_VERIFY_FAILED and certifi is installed,
        retry with certifi.
    """
    def _open_with_context(ctx):
        if ctx is None:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as resp:
                return resp.read().decode("utf-8", errors="strict")
        else:
            opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
            with opener.open(url, timeout=TIMEOUT) as resp:
                return resp.read().decode("utf-8", errors="strict")

    certifi_ctx = None
    if use_certifi_first:
        try:
            import certifi  # type: ignore
            certifi_ctx = ssl.create_default_context(cafile=certifi.where())
            return _open_with_context(certifi_ctx)
        except Exception:
            certifi_ctx = None  # fall back to default

    # Try default context
    try:
        return _open_with_context(None)
    except ssl.SSLCertVerificationError:
        # Retry with certifi if available
        try:
            if certifi_ctx is None:
                import certifi  # type: ignore
                certifi_ctx = ssl.create_default_context(cafile=certifi.where())
            return _open_with_context(certifi_ctx)
        except Exception as e:
            raise RuntimeError(
                "TLS certificate verification failed. "
                "Install certificates for this Python (run 'Install Certificates.command') "
                "or 'pip install certifi'. Original error: " + repr(e)
            ) from e

def read_or_fetch(url: str, local_name: str, *, cache_dir_env: str = "UNICODE_CACHE_DIR") -> str:
    """
    If $UNICODE_CACHE_DIR/local_name exists, read it from disk.
    Otherwise, fetch from the URL.
    """
    cache_dir = os.environ.get(cache_dir_env)
    if cache_dir:
        p = os.path.join(cache_dir, local_name)
        if os.path.isfile(p):
            with open(p, "r", encoding="utf-8") as f:
                return f.read()
    return fetch(url)

# --- Config ---
USE_GRAPHEME_BASE = True  # True = Unicode-correct (Grapheme_Base). False = gc heuristic (L., N., S., Zs).
TIMEOUT = 30

URL_UNICODEDATA = "https://www.unicode.org/Public/UNIDATA/UnicodeData.txt"
URL_DERIVED = "https://www.unicode.org/Public/UNIDATA/DerivedCoreProperties.txt"

HEADER = "code;charname;gc;ccc;bc;cdm;ddv;dv;nv;m;u1n;comment;upper;lower;title\n"
GC_REGEX = re.compile(r"^(?:L.|N.|S.|Zs)$")  # Letters, Numbers, Symbols, exactly Zs


def parse_unicode_data(text: str) -> list[tuple[int, str]]:
    data = HEADER + text
    reader = csv.DictReader(io.StringIO(data), delimiter=";")
    out: list[tuple[int, str]] = []
    for row in reader:
        code = row.get("code")
        gc = row.get("gc", "")
        if not code:
            continue
        try:
            out.append((int(code, 16), gc))
        except ValueError:
            pass
    return out

def parse_derived_props(text: str, prop_name: str) -> set[int]:
    # Lines look like:
    #   0300..036F    ; Grapheme_Extend # Mn  [112] COMBINING GRAVE ACCENT..COMBINING LATIN SMALL LETTER X
    #   00AD          ; Default_Ignorable_Code_Point # Cf SOFT HYPHEN
    prop_re = re.compile(r"^\s*([0-9A-Fa-f]{4,6})(?:\.\.([0-9A-Fa-f]{4,6}))?\s*;\s*([A-Za-z0-9_]+)")
    result: set[int] = set()
    for line in text.splitlines():
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

def ranges_from_sorted(nums: list[int]) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for _, grp in groupby(enumerate(nums), key=lambda t: t[1] - t[0]):
        g = list(grp)
        out.append((g[0][1], g[-1][1]))
    return out

def main() -> None:
    if USE_GRAPHEME_BASE:
        dcp = fetch(URL_DERIVED)
        base = parse_derived_props(dcp, "Grapheme_Base")
        ignorable = parse_derived_props(dcp, "Default_Ignorable_Code_Point")
        codes = sorted(base - ignorable)
    else:
        udata = fetch(URL_UNICODEDATA)
        rows = parse_unicode_data(udata)
        codes = sorted({cp for (cp, gc) in rows if GC_REGEX.match(gc)})

    for start, end in ranges_from_sorted(codes):
        length = end - start + 1
        print(f"[set addCharactersInRange:NSMakeRange({hex(start)}, {length})];")

if __name__ == "__main__":
    main()
