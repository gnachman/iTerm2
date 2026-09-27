#!/usr/bin/env python3
"""Find string literals passed to AppKit UI-facing sinks, in ObjC and Swift.

The sink set is harvested from clang's LocalizationChecker.cpp initUIMethods()
table (the authoritative "user-facing text" list the analyzer uses), restricted
to the macOS NS* classes and reduced to the distinctive keyword tokens that
immediately precede the string argument. Unlike the clang analyzer this also
covers Swift and format/assembled arguments (by flagging them non-trivial).
"""
import os, re, sys, json

# selector keywords (ObjC) that take a user-facing NSString as the NEXT argument
OBJC_SELECTORS = [
    "setTitle","setAlternateTitle","setStringValue","setPlaceholderString","setToolTip",
    "setLabel","setPaletteLabel","setMessage","setMessageText","setInformativeText","setPrompt",
    "setNameFieldLabel","setNameFieldStringValue","setBadgeLabel","setHeaderToolTip","setActionName",
    "setSubtitle","setActionButtonTitle","setOtherButtonTitle","setResponsePlaceholder",
    "setMiniwindowTitle","setDefaultButtonTitle","setString","setDiscoverabilityTitle",
    "setLocalizedDescription","setLocalizedAdditionalDescription","setAccessibilityLabel",
    "setAccessibilityTitle","setAccessibilityHelp","setAccessibilityValueDescription",
    "setAccessibilityPlaceholderValue","setAccessibilityHint","setAccessibilityDescription",
    "initWithTitle","initWithString","addItemWithTitle","insertItemWithTitle","addButtonWithTitle",
    "buttonWithTitle","radioButtonWithTitle","checkboxWithTitle","selectItemWithTitle",
    "removeItemWithTitle","labelWithString","wrappingLabelWithString","textFieldWithString",
    # mid-selector labeled arguments (e.g. initWithTitle:action:keyEquivalent:, rowActionWithStyle:title:)
    "title","label","message","informativeText","prompt",
]
# property names settable to a user-facing string (ObjC dot-syntax and Swift)
PROPS = [
    "title","alternateTitle","stringValue","placeholderString","toolTip","label","paletteLabel",
    "message","messageText","informativeText","prompt","string","subtitle","actionName",
    "miniwindowTitle","badgeLabel","headerToolTip","nameFieldLabel","nameFieldStringValue",
    "responsePlaceholder","actionButtonTitle","otherButtonTitle","defaultButtonTitle",
    "discoverabilityTitle","localizedDescription","localizedAdditionalDescription",
    "accessibilityLabel","accessibilityTitle","accessibilityHelp","accessibilityValueDescription",
    "accessibilityPlaceholderValue","accessibilityHint","accessibilityDescription",
]
# Swift initializer / labeled-arg keywords
SWIFT_LABELS = ["title","label","message","messageText","informativeText","prompt","string",
                "placeholderString","stringValue","toolTip","alternateTitle"]

sel_alt = "|".join(sorted(set(OBJC_SELECTORS), key=len, reverse=True))
prop_alt = "|".join(sorted(set(PROPS), key=len, reverse=True))
swlabel_alt = "|".join(sorted(set(SWIFT_LABELS), key=len, reverse=True))

# ObjC: <sink> then optionally a [NSString [localized]stringWithFormat:] wrapper, then @"literal".
# The wrapper group lets us catch  setStringValue:[NSString stringWithFormat:@"...%@...", x]
# where the format literal sits one bracket removed from the sink.
OBJC_SINK = r'(?:\b(?:' + sel_alt + r')\s*:|\.(?:' + prop_alt + r')\s*=)\s*'
OBJC_WRAP = r'(?P<wrap>\[\s*NSString\s+(?:localizedStringWithFormat|stringWithFormat)\s*:\s*)?'
OBJC_RE   = re.compile(OBJC_SINK + OBJC_WRAP + r'@"(?P<lit>(?:[^"\\]|\\.)*)"')
# Swift: .<prop> = "literal"    OR   <label>: "literal"
SW_PROP_RE = re.compile(r'\.(' + prop_alt + r')\s*=\s*"((?:[^"\\]|\\.)*)"')
SW_LBL_RE  = re.compile(r'\b(' + swlabel_alt + r')\s*:\s*"((?:[^"\\]|\\.)*)"')

FMT = re.compile(r'%([0-9]+\$)?(ll|l|z|h)?[@dDuUxXeEfFgGcsp]|%\d*\.\d+f')  # real ObjC format specifier
SWINTERP = re.compile(r'\\\(')  # Swift interpolation

def walk():
    for root,_,files in os.walk("sources"):
        for f in files:
            if f.endswith((".m",".mm",".swift")):
                yield os.path.join(root,f)

rows=[]
for path in walk():
    swift = path.endswith(".swift")
    try: lines=open(path,encoding="utf-8",errors="replace").read().splitlines()
    except: continue
    for i,line in enumerate(lines,1):
        hits=[]  # (sink, literal, wrapped_in_format)
        if swift:
            for m in SW_PROP_RE.finditer(line): hits.append((m.group(1),m.group(2),False))
            for m in SW_LBL_RE.finditer(line):  hits.append((m.group(1),m.group(2),False))
        else:
            for m in OBJC_RE.finditer(line):
                hits.append(("objc-sink", m.group("lit"), bool(m.group("wrap"))))
        for sink,lit,wrapped in hits:
            if lit.strip()=="" : bucket="skip"           # empty string
            elif swift and SWINTERP.search(lit): bucket="nontrivial"  # interpolation = plural/format
            elif (not swift) and (wrapped or FMT.search(lit) or "stringByAppendingString" in line):
                bucket="nontrivial"                      # format string feeding a UI sink
            else: bucket="trivial"
            rows.append((path[len("sources/"):], i, "swift" if swift else "objc", sink, bucket, lit))

# de-dupe identical (file,line,sink,lit)
seen=set(); uniq=[]
for r in rows:
    k=(r[0],r[1],r[3],r[5])
    if k in seen: continue
    seen.add(k); uniq.append(r)

buckets={}
for r in uniq: buckets.setdefault(r[4],[]).append(r)
hdr="file\tline\tlang\tsink\tbucket\tliteral\n"
outdir=sys.argv[1] if len(sys.argv)>1 else "tmp"
os.makedirs(outdir, exist_ok=True)
for b,rs in buckets.items():
    open(f"{outdir}/ui_{b}.tsv","w").write(hdr+"\n".join("\t".join(map(str,r)) for r in sorted(rs)))
open(f"{outdir}/ui_all.tsv","w").write(hdr+"\n".join("\t".join(map(str,r)) for r in sorted(uniq)))

def by(lang,bucket): return sum(1 for r in uniq if r[2]==lang and r[4]==bucket)
print(f"total unique sink+literal sites: {len(uniq)}")
for b in ("trivial","nontrivial","skip"):
    print(f"  {b:11} {len(buckets.get(b,[])):5}   (objc {by('objc',b)}, swift {by('swift',b)})")
