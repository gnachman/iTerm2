#!/usr/bin/env python3
"""
build_stored_state_corpus.py

Builds tests/stored-state-corpus/ from the raw corpus collected on vm1
(tmp/stored-state-corpus/, not committed) and proves the result:

  1. stored_state_sanitize.py sanitizes the selected files into a new
     scratch directory (same-length placeholders, structure untouched);
  2. stored_state_scan.py, which shares no code with the sanitizer, finds
     no private value and no detector hit in the output;
  3. stored_state_digest.py finds every file's structural digest identical
     to the original's (keys, types, number widths, lengths, keyed-archive
     class tables, SQLite schemas and rowids);
  4. every plist, top-level or nested in a SQLite blob, passes
     `plutil -lint` (when plutil exists) and plistlib;
  5. manifest.json is written with each file's origin, how it was made,
     its SHA-256, and what was replaced.

Only if all of that passes is the output moved to DEST.

USAGE
  build_stored_state_corpus.py --values V.json [--raw RAW] [--dest DEST]
      [--work WORKDIR]

The values file holds the private values and is never committed; see
stored_state_sanitize.py for its format. Python 3 standard library only.
"""

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

ALL_SETS = ["3.4.0", "3.4.0-restore1", "3.5.0", "3.5.0-restore1", "3.6.0",
            "3.6.0-restore1", "3.7.8", "3.7.8-restore1",
            "upgraded-3.4.0-to-3.7.8", "upgraded-3.5.0-to-3.7.8"]
AS = "home/Library/Application Support/iTerm2/"

# What is committed. Everything else in the raw corpus is listed in LEFT_OUT.
SELECTION = []
for _s in ALL_SETS:
    SELECTION += [
        f"{_s}/home/Library/Preferences/com.googlecode.iterm2.plist",
        f"{_s}/home/Library/Preferences/com.googlecode.iterm2.private.plist",
        f"{_s}/{AS}pbhistory.plist",
        f"{_s}/{AS}DynamicProfiles/fake-dynamic.json",
        f"{_s}/{AS}version.txt",
        f"{_s}/{AS}ShellHistory.sqlite",
    ]
for _s in ALL_SETS[2:]:  # 3.4.0 kept snippets in user defaults
    SELECTION.append(f"{_s}/{AS}snippets.plist")
for _s in ["3.4.0", "3.4.0-restore1", "3.7.8", "upgraded-3.4.0-to-3.7.8"]:
    SELECTION.append(f"{_s}/{AS}SavedState/restorable-state.sqlite")
for _s in ["3.4.0", "3.5.0", "3.6.0", "3.7.8"]:
    SELECTION.append(f"{_s}/home/corpus-fake/fake-all-profiles.json")
SELECTION += [
    f"3.7.8/{AS}chatdb.sqlite",
    "3.4.0/home/corpus-prefs/com.googlecode.iterm2.plist",
    "3.7.8/home/corpus-prefs/Data/snippets.plist",
    "upgraded-3.4.0-to-3.7.8/home/corpus-prefs/Data/snippets.plist",
    "upgraded-3.5.0-to-3.7.8/home/corpus-prefs/Data/snippets.plist",
]

LEFT_OUT = [
    ("*/home/corpus-fake/fake-export.itermexport",
     "gzip tar of copies of the other files plus shell integration scripts "
     "(0.5 to 1.1 MB each); the sanitizer does not rewrite gzip or tar "
     "containers"),
    ("<other sets>/" + AS + "SavedState/restorable-state.sqlite",
     "size: 3.5.0, 3.5.0-restore1, 3.6.0, 3.6.0-restore1, 3.7.8-restore1 and "
     "upgraded-3.5.0-to-3.7.8 are 0.6 to 1.5 MB each; sanitized and proven "
     "like the rest, not committed (see the README)"),
    ("<other sets>/home/corpus-prefs/com.googlecode.iterm2.plist",
     "size: 0.3 to 0.7 MB each, the same content as the set's main plist in "
     "XML; 3.4.0's is kept as the example of the format"),
    ("*-restore1/home/corpus-fake/fake-all-profiles.json, upgraded-*/...",
     "byte-identical to the final set of the same version"),
    ("<other sets>/" + AS + "chatdb.sqlite",
     "empty AI chat database, schema identical to 3.7.8's"),
    ("*/" + AS + "parsers/*, */home/Library/Caches/com.googlecode.iterm2/parsers/*",
     "CoreParse grammar caches (NSKeyedArchiver, classes CPGrammar, "
     "CPGrammarSymbol, CPRule, CPShiftReduceAction, CPShiftReduceActionTable, "
     "CPShiftReduceGotoTable); regenerated when missing, 0.1 to 0.2 MB each"),
    ("*/home/Library/Caches/com.googlecode.iterm2/Cache.db, "
     "*/home/Library/HTTPStorages/com.googlecode.iterm2/httpstorages.sqlite",
     "Apple URL cache and HTTP storage, not iTerm2 state"),
    ("*.sqlite-wal, *.sqlite-shm",
     "the WAL was applied to the database before sanitizing (a byte-patched "
     "WAL fails its checksums); the index is rebuilt by SQLite"),
    ("*/" + AS + "SavedState/lock, iterm2-daemon-1.socket.lock, chatdb-lock",
     "empty lock files"),
    ("*/home/.config/iterm2/*",
     "symbolic links into the app bundle the VM ran, not a stored format"),
    ("*/manifest.json, */changed-since-launch.txt",
     "collection metadata; the recipe (steps) is copied into manifest.json, "
     "the file list of the VM's home directory is not kept"),
]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=600, **kw)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def nested_plists_ok(path):
    """Every blob in a SQLite file that looks like a plist parses."""
    n = 0
    con = sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)
    try:
        tables = [r[0] for r in con.execute(
            "select name from sqlite_master where type='table'")]
        for t in tables:
            for row in con.execute(f'select * from "{t}"'):
                for v in row:
                    if isinstance(v, bytes) and v[:8] == b"bplist00":
                        plistlib.loads(v)
                        n += 1
    finally:
        con.close()
    return n


def origin_version(set_name):
    m = re.match(r"upgraded-(.+)-to-(.+)", set_name)
    if m:
        return f"{m.group(1)}, then {m.group(2)} launched once on it"
    return set_name.split("-")[0]


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--values", required=True)
    ap.add_argument("--raw", default=os.path.join(REPO, "tmp/stored-state-corpus"))
    ap.add_argument("--dest", default=os.path.join(REPO, "tests/stored-state-corpus"))
    ap.add_argument("--work", help="scratch directory (default: a new one in tmp/)")
    args = ap.parse_args(argv)

    work = args.work or tempfile.mkdtemp(prefix="stored-state-build-",
                                         dir=os.path.join(REPO, "tmp"))
    out = os.path.join(work, "out")
    py = [sys.executable, "-I"]
    include = ["^" + re.escape(p) + "$" for p in SELECTION]
    inc_args = [a for p in include for a in ("--include", p)]

    r = run(py + [os.path.join(HERE, "stored_state_sanitize.py"), "sanitize",
                  "--values", args.values] + inc_args + [args.raw, out])
    if r.returncode:
        print(r.stderr, file=sys.stderr)
        return 1
    results = json.loads(r.stdout)
    missing = [p for p in SELECTION if p not in results]
    if missing:
        print(f"selected files missing from the raw corpus: {missing}", file=sys.stderr)
        return 1

    proofs = {}
    r = run(py + [os.path.join(HERE, "stored_state_scan.py"), "--values",
                  args.values, out])
    proofs["scan"] = {"exit": r.returncode, "summary": r.stderr.strip(),
                      "findings": r.stdout.strip().splitlines()}
    r = run(py + [os.path.join(HERE, "stored_state_digest.py"), "compare",
                  "--json", "--key-map", args.values, args.raw, out] + SELECTION)
    digest = json.loads(r.stdout) if r.stdout.strip() else {}
    proofs["digest"] = {"exit": r.returncode, "summary": r.stderr.strip()}

    lint = {"plutil": shutil.which("plutil") is not None, "failures": [],
            "files": 0, "nested": 0}
    for rel in SELECTION:
        full = os.path.join(out, rel)
        with open(full, "rb") as f:
            head = f.read(16)
        if rel.endswith(".plist"):
            lint["files"] += 1
            if lint["plutil"]:
                lr = run(["plutil", "-lint", full])
                if lr.returncode:
                    lint["failures"].append(rel)
        elif head == b"SQLite format 3\x00":
            try:
                lint["nested"] += nested_plists_ok(full)
            except Exception as e:  # noqa: BLE001 - recorded as a failure
                lint["failures"].append(f"{rel}: {e}")
    proofs["lint"] = lint

    ok = (proofs["scan"]["exit"] == 0 and proofs["digest"]["exit"] == 0 and
          not lint["failures"])
    if not ok:
        json.dump(proofs, sys.stderr, indent=1)
        print(f"\nproof failed; output left in {out}", file=sys.stderr)
        return 1

    with open(args.values, "r", encoding="utf-8") as f:
        spec = json.load(f)
    placeholders = {}
    for e in spec["literals"]:
        if e.get("placeholder"):
            placeholders.setdefault(e["kind"], []).append(e["placeholder"])

    sets = {}
    for s in ALL_SETS:
        mp = os.path.join(args.raw, s, "manifest.json")
        # Origin metadata, sanitized by the same engine as everything else.
        r = run(py + [os.path.join(HERE, "stored_state_sanitize.py"), "sanitize",
                      "--values", args.values, "--include",
                      "^" + re.escape(f"{s}/manifest.json") + "$", args.raw,
                      os.path.join(work, "meta", s)])
        if r.returncode:
            print(r.stderr, file=sys.stderr)
            return 1
        with open(os.path.join(work, "meta", s, s, "manifest.json")) as f:
            meta = json.load(f)
        meta.pop("files", None)
        sets[s] = meta
        assert os.path.exists(mp)

    files = []
    for rel in SELECTION:
        res = results[rel]
        d = digest.get(rel, {})
        files.append({
            "path": rel,
            "set": rel.split("/", 1)[0],
            "origin_version": origin_version(rel.split("/", 1)[0]),
            "format": res["format"],
            "size": os.path.getsize(os.path.join(out, rel)),
            "sha256": sha256(os.path.join(out, rel)),
            "produced": ("written by iTerm2 on vm1 (see sets.<set>.steps); "
                         "sanitized by tools/swift_migration/stored_state_sanitize.py"
                         + ("; WAL applied, rebuilt with rowids kept" if res["format"] == "sqlite"
                            else "")),
            "replaced": res.get("replaced", {}),
            "replaced_at": res.get("replaced_paths", []),
            "renamed_keys": res.get("renamed_keys", 0),
            "keyed_archive_classes": d.get("archive_classes", 0),
        })

    manifest = {
        "about": "Sanitized stored state written by released iTerm2 versions. "
                 "See README.md.",
        "placeholders": placeholders,
        "proofs": {
            "scan": proofs["scan"]["summary"],
            "digest": proofs["digest"]["summary"],
            "plists_linted": lint["files"],
            "plutil_used": lint["plutil"],
            "nested_plists_parsed": lint["nested"],
        },
        "sets": sets,
        "files": files,
        "left_out": [{"path": p, "reason": why} for p, why in LEFT_OUT],
    }
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
        f.write("\n")

    # Keep a hand-written README if DEST already has one.
    readme = os.path.join(args.dest, "README.md")
    if os.path.exists(readme):
        shutil.copyfile(readme, os.path.join(out, "README.md"))
    # The manifest and README are new text: scan the whole output again.
    r = run(py + [os.path.join(HERE, "stored_state_scan.py"), "--values",
                  args.values, out])
    if r.returncode:
        print(r.stdout + r.stderr, file=sys.stderr)
        print(f"final scan failed; output left in {out}", file=sys.stderr)
        return 1
    if os.path.exists(args.dest):
        shutil.rmtree(args.dest)
    shutil.move(out, args.dest)
    print(json.dumps(manifest["proofs"], indent=1))
    print(f"wrote {args.dest} ({sum(f['size'] for f in files)} bytes in "
          f"{len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
