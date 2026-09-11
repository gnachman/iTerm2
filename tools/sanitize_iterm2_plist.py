#!/usr/bin/env python3
"""
sanitize_iterm2_plist.py

Surgically redact private information from an iTerm2 user-defaults plist
(com.googlecode.iterm2.plist) so it can be shared for debugging without
leaking commands, terminal contents, text-to-send, paths, hostnames,
usernames, URLs, credentials, regexes, or AI prompts.

The goal is SURGICAL redaction: we keep the structure (so iTerm2 can still
load the file) and only replace the values that can contain private data.
Colors, fonts, sizes, booleans, enums, and GUIDs are left untouched.

Only user defaults are handled here. Ancillary files (ShellHistory.sqlite,
pbhistory.plist, chatdb.sqlite, notes RTFD, snippets.plist on disk, saved
window state, etc.) are intentionally out of scope.

USAGE
    python3 sanitize_iterm2_plist.py INPUT.plist [-o OUTPUT.plist]
    python3 sanitize_iterm2_plist.py INPUT.plist --in-place
    python3 sanitize_iterm2_plist.py INPUT.plist --dry-run
    python3 sanitize_iterm2_plist.py INPUT.plist --aggressive

By default a sibling "com.googlecode.iterm2.private.plist" (which holds the
find-bar search history under NoSyncSearchHistory2) is also sanitized when
the main plist is passed; use --no-private to skip it.

--aggressive additionally redacts lower-sensitivity labels: profile names,
descriptions, tags, titles, model names, and the installation id.

-----------------------------------------------------------------------------
AUDIT: locations in user defaults that may hold private information
-----------------------------------------------------------------------------
Everything below is redacted by the rules in this file. Key literals are the
strings as they appear in the plist; the source constant is noted for
traceability.

TOP-LEVEL keys
  New Bookmarks / Default Bookmark ....... array/dict of profiles (recursed)
  GlobalKeyMap / GlobalTouchBarMap ....... key bindings; action "Text" param
  Actions ................................ named actions; "parameter"
  PointerActions ......................... gesture/mouse actions; "Argument"
  Snippets, NoSyncSnippetsSupersededFallbackBackup,
    NoSyncSnippetsDiscardedFallbackBackup  snippet "value"/"title"/"tags"
  Window Arrangements .................... deep session state (recursed)
  Default Arrangement Name ............... arrangement name (label; aggressive)
  Workgroups ............................. JSON Data: command/perFileCommand/
                                           urlString/displayName/name
  CodeReviewSavedPrompts ................. JSON Data: prompt name/text
  StatusPriorityEntries .................. JSON Data: status "pattern"
  Coprocess MRU, NoSyncCoprocessCommandsToIgnoreErrorOutput,
    FileDropCoprocess, UrlHandlerCommand   user shell commands
  NoSyncKnownHosts ....................... user@host:port list
  NoSyncWorkgroupGitBaseRecents .......... git base/ref recents
  NoSyncRecentArchives ................... archive file paths
  NoSyncRecordedVariables ................ recorded variable names (deep)
  NoSyncSearchHistory[2] ................. find-bar search terms
  NoSyncOpenAIAPIKey ..................... legacy plaintext API key
  NoSyncCompanion* ....................... push token / paired id / relay
                                           origin (string values only)
  NoSyncInstallationId ................... persistent install identifier
  AICustomHeaders ........................ auth headers (name/value, deep)
  AIManualModelConfigurations ............ custom endpoint "url" (+ name)
  AitermURL, AiProxy, AiModel, AIEconomyModelName  AI endpoint/model
  AI Prompt* (11 keys), CodeciergeGhostRidingPrompt, CodeciergeRegularPrompt
                                           user-authored AI prompt templates
  PrefsCustomFolder, CustomScriptsFolder, DownloadsDirectory,
    ScreenshotSaveLocation, PreferredBaseDir, DynamicProfilesPath,
    GitSearchPath, PathsToIgnore, NativeRenderingCSSLight/Dark,
    BrowserPluginPathHint, ImportPath, NoSyncLastSSHDirectory  paths
  NoSyncSavePanelSavedSettings_* ......... nested "InitialDirectory" path
  PathToDatabase_* ....................... password-manager backend URL
  OnePasswordAccount, LastpassGroups ..... password-manager identifiers
  FakeFullyQualifiedDomainName, AlternateSSHIntegrationScript, SshSchemePath
  PasteSpecialRegex, PasteSpecialSubstitution
  SessionEndMessageText, SessionRestartedMessageText,
    SessionFinishedMessageText, TmuxTitlePrefix, NoSyncVariablesToReport,
    AlternateMouseScrollStringForUp/ForDown  user text

PROFILE fields (inside New Bookmarks[*], Default Bookmark, and profiles
embedded in arrangements under Bookmark / Initial Profile)
  Command, Initial Text, Initial URL, Working Directory, Badge Text,
  Subtitle, Custom Window Title, Custom Tab Title, Answerback String,
  Custom Icon Path, Background Image Location, Background Image Folder
  Location, AWDS Window/Tab/Pane Directory, Log Directory, Log Filename
  Format, Archive Directory, Browser Extensions Root, Dynamic Profile
  Filename, Custom Locale, Bound Hosts, Jobs to Ignore, Snippets Filter,
  tmux Pane Title
  Nested: Triggers, Smart Selection Rules, Keyboard Map, Touch Bar Map,
          SSH, Semantic History, Status Bar Layout, Bindings
  Kept (NOT sensitive): Custom Command / Custom Directory / AWDS *Option
          (enums), colors, fonts, sizes, GUIDs, hotkey codes.
  Labels (aggressive only): Name, Description, Tags, Title Function.

TRIGGERS (profile "Triggers")
  regex, contentregex, parameter (skipped for Highlight triggers whose
  parameter encodes colors), eventParams.* (deep). Kept: action (class),
  matchType, partial, disabled, performance, provenance.

SMART SELECTION (profile "Smart Selection Rules")
  regex, actions[*].parameter (+ title/notes under --aggressive).
  Kept: precision, actions[*].action (enum).

KEY BINDINGS (GlobalKeyMap / GlobalTouchBarMap / profile Keyboard Map /
Touch Bar Map / Actions / status bar action knob)
  Text (parameter), Label. Kept: Action, Version, Escaping, Apply Mode.

STATUS BAR (profile "Status Bar Layout")
  expression (Swifty-string component). Action components store an embedded
  key-binding dict whose "Text" is caught by the key-binding rule. RPC
  components with script-defined knob keys are only partially covered.

WINDOW ARRANGEMENTS -> session dicts (SESSION_ARRANGEMENT_*)
  Removed:  Contents, Clippings, Clippings Archive, Session Note, Conductor,
            Conductor Parser Tree, Reusable Cookie, Browser State,
            Hostname to Shell, Tmux History, Tmux AltHistory, Tmux State
  Redacted: Working Directory, Program.Command, Environment (deep),
            Variables (deep), Substitutions (deep), Commands,
            Name Controller State (deep), Server Dict (deep),
            AutoLog File Name, Filter, Browser Target,
            Code Review Last Prompt, Bookmark (profile), Workgroup (recursed)
  Kept: Columns, Rows, Session GUID/Stable ID, geometry, flags.
-----------------------------------------------------------------------------
"""

import argparse
import json
import os
import plistlib
import sys

REDACT = "[redacted]"

# Actions
REMOVE = "remove"   # delete the key entirely
REDACT_V = "redact"  # replace the value (strings anywhere within -> REDACT)
JSON_V = "json"     # value is JSON (bytes/str): decode, recurse, re-encode

# Trigger subclasses whose "parameter" encodes colors, not private text.
HIGHLIGHT_ACTIONS = {"HighlightTrigger", "iTermHighlightLineTrigger"}

# Keys whose *values* are always private content. Matched by exact key name
# anywhere in the tree (values only; dict keys are never matched), so nested
# and embedded structures are covered automatically by the recursive walk.
CONTENT_KEYS = {
    # commands / coprocesses
    "Command": REDACT_V,
    "command": REDACT_V,
    "perFileCommand": REDACT_V,
    "Commands": REDACT_V,
    "Coprocess MRU": REDACT_V,
    "NoSyncCoprocessCommandsToIgnoreErrorOutput": REDACT_V,
    "FileDropCoprocess": REDACT_V,
    "UrlHandlerCommand": REDACT_V,
    "AlternateSSHIntegrationScript": REDACT_V,
    "SshSchemePath": REDACT_V,
    # text sent to the terminal / key-binding & action parameters
    "Text": REDACT_V,
    "Label": REDACT_V,            # key-binding / touch-bar button label (user text)
    "parameter": REDACT_V,        # highlight-trigger exception handled below
    "Argument": REDACT_V,
    "value": REDACT_V,
    "Initial Text": REDACT_V,
    "Answerback String": REDACT_V,
    "expression": REDACT_V,       # status bar Swifty-string component
    "AlternateMouseScrollStringForUp": REDACT_V,
    "AlternateMouseScrollStringForDown": REDACT_V,
    # terminal contents / captured output
    "Contents": REMOVE,
    "Clippings": REMOVE,
    "Clippings Archive": REMOVE,
    "Session Note": REMOVE,
    "Tmux History": REMOVE,
    "Tmux AltHistory": REMOVE,
    "Tmux State": REMOVE,
    "Code Review Last Prompt": REDACT_V,
    # regexes / patterns
    "regex": REDACT_V,
    "contentregex": REDACT_V,
    "pattern": REDACT_V,
    "PasteSpecialRegex": REDACT_V,
    "PasteSpecialSubstitution": REDACT_V,
    # filesystem paths / directories
    "Working Directory": REDACT_V,
    "Custom Icon Path": REDACT_V,
    "Background Image Location": REDACT_V,
    "Background Image Folder Location": REDACT_V,
    "AWDS Window Directory": REDACT_V,
    "AWDS Tab Directory": REDACT_V,
    "AWDS Pane Directory": REDACT_V,
    "Log Directory": REDACT_V,
    "Log Filename Format": REDACT_V,
    "Archive Directory": REDACT_V,
    "Browser Extensions Root": REDACT_V,
    "Dynamic Profile Filename": REDACT_V,
    "AutoLog File Name": REDACT_V,
    "ImportPath": REDACT_V,
    "PrefsCustomFolder": REDACT_V,
    "CustomScriptsFolder": REDACT_V,
    "DownloadsDirectory": REDACT_V,
    "ScreenshotSaveLocation": REDACT_V,
    "PreferredBaseDir": REDACT_V,
    "DynamicProfilesPath": REDACT_V,
    "GitSearchPath": REDACT_V,
    "PathsToIgnore": REDACT_V,
    "NativeRenderingCSSLight": REDACT_V,
    "NativeRenderingCSSDark": REDACT_V,
    "BrowserPluginPathHint": REDACT_V,
    "NoSyncLastSSHDirectory": REDACT_V,
    "NoSyncRecentArchives": REDACT_V,
    "InitialDirectory": REDACT_V,
    # hosts / URLs
    "Bound Hosts": REDACT_V,
    "NoSyncKnownHosts": REDACT_V,
    "Hostname to Shell": REMOVE,
    "urlString": REDACT_V,
    "url": REDACT_V,
    "Initial URL": REDACT_V,
    "Browser Target": REDACT_V,
    "Browser State": REMOVE,
    "AitermURL": REDACT_V,
    "AiProxy": REDACT_V,
    "FakeFullyQualifiedDomainName": REDACT_V,
    "NoSyncWorkgroupGitBaseRecents": REDACT_V,
    # environment / variables / remote state (deep: every string within)
    "Environment": REDACT_V,
    "Variables": REDACT_V,
    "Substitutions": REDACT_V,
    "NoSyncRecordedVariables": REDACT_V,
    "NoSyncVariablesToReport": REDACT_V,
    "Bindings": REDACT_V,
    "Server Dict": REDACT_V,
    "Name Controller State": REDACT_V,
    "eventParams": REDACT_V,
    "SSH": REDACT_V,
    "Conductor": REMOVE,
    "Conductor Parser Tree": REMOVE,
    "Reusable Cookie": REMOVE,
    # credentials / device & install identifiers
    "NoSyncOpenAIAPIKey": REDACT_V,
    "AICustomHeaders": REDACT_V,
    "OnePasswordAccount": REDACT_V,
    "LastpassGroups": REDACT_V,
    "NoSyncInstallationId": REDACT_V,        # persistent install identifier
    "NoSyncCompanionMainRelayOrigin": REDACT_V,  # may be a self-hosted relay URL
    # interpolated user text / labels that are effectively content
    "Badge Text": REDACT_V,
    "Subtitle": REDACT_V,
    "Custom Window Title": REDACT_V,
    "Custom Tab Title": REDACT_V,
    "Title Override": REDACT_V,
    "Tab Group Name": REDACT_V,
    "tmux Pane Title": REDACT_V,
    "Custom Locale": REDACT_V,
    "Jobs to Ignore": REDACT_V,
    "Snippets Filter": REDACT_V,
    # semantic history + AI prompts + code-review prompt text
    "text": REDACT_V,
    "AI Prompt": REDACT_V,
    "AI Prompt for AI Chat with no function calling": REDACT_V,
    "AI Prompt for AI Chat with ReadOnlyTerminal": REDACT_V,
    "AI Prompt for AI Chat with ReadWriteTerminal": REDACT_V,
    "AI Prompt for AI Chat with Browser": REDACT_V,
    "AI Prompt for AI Chat with ReadOnlyTerminalBrowser": REDACT_V,
    "AI Prompt for AI Chat with ReadWriteTerminalBrowser": REDACT_V,
    "AI Prompt for AI Chat Orchestration": REDACT_V,
    "AI Prompt for Code Review": REDACT_V,
    "AI Prompt for Code Review System": REDACT_V,
    "AI Prompt for Chat Icon": REDACT_V,
    "CodeciergeGhostRidingPrompt": REDACT_V,
    "CodeciergeRegularPrompt": REDACT_V,
    # find-bar search history
    "NoSyncSearchHistory2": REDACT_V,
    "NoSyncSearchHistory": REDACT_V,  # legacy; no-op if it holds a bool
    # user-authored session messages
    "SessionEndMessageText": REDACT_V,
    "SessionRestartedMessageText": REDACT_V,
    "SessionFinishedMessageText": REDACT_V,
    "TmuxTitlePrefix": REDACT_V,
    # JSON-in-Data blobs (decode, recurse with the same rules, re-encode)
    "Workgroups": JSON_V,
    "CodeReviewSavedPrompts": JSON_V,
    "StatusPriorityEntries": JSON_V,
}

# Lower-sensitivity labels, only redacted with --aggressive.
LABEL_KEYS = {
    "Name": REDACT_V,
    "name": REDACT_V,
    "Description": REDACT_V,
    "Tags": REDACT_V,
    "title": REDACT_V,
    "notes": REDACT_V,
    "displayName": REDACT_V,
    "Title Function": REDACT_V,
    "Dynamic Profile Parent Name": REDACT_V,
    "Default Arrangement Name": REDACT_V,
    "AiModel": REDACT_V,
    "AIEconomyModelName": REDACT_V,
    "TTY": REDACT_V,
}

# Top-level keys matched by prefix (value is a private string/dict).
# REDACT_V leaves bools/ints untouched, so a broad NoSyncCompanion prefix only
# scrubs the string-valued push token / paired id / relay origin.
PREFIX_CONTENT = [
    ("PathToDatabase_", REDACT_V),
    ("NoSyncCompanion", REDACT_V),
    ("NoSyncSavePanelSavedSettings_", None),  # None => recurse (hits InitialDirectory)
]


class Report:
    def __init__(self):
        self.entries = []  # (breadcrumb, action, note)

    def add(self, path, action, note=""):
        self.entries.append(("/".join(path) if path else "<root>", action, note))

    def summary(self):
        from collections import Counter
        by_top = Counter()
        for path, _, _ in self.entries:
            top = path.split("/", 1)[0]
            by_top[top] += 1
        return by_top


def redact_value(value, report, path):
    """Return value with every string within it replaced by REDACT.

    Numbers, bools, and dates are preserved. Bytes are dropped to empty.
    Dict keys are preserved (they are variable/host/header names, not the
    secret); only their string values are redacted.
    """
    if isinstance(value, str):
        return REDACT if value else value
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, bytes):
        return b""
    if isinstance(value, list):
        return [redact_value(v, report, path) for v in value]
    if isinstance(value, dict):
        return {k: redact_value(v, report, path + [str(k)]) for k, v in value.items()}
    return value  # datetime and anything else: not private


def redact_json(value, aggressive, report, path):
    """value is Data (bytes) or a str holding JSON. Decode, scrub, re-encode."""
    was_bytes = isinstance(value, (bytes, bytearray))
    try:
        text = value.decode("utf-8") if was_bytes else value
        data = json.loads(text)
    except (UnicodeDecodeError, json.JSONDecodeError, AttributeError):
        # Not JSON (perhaps a keyed-archive). Drop it wholesale to be safe.
        report.add(path, "drop-opaque-data")
        return b"" if was_bytes else ""
    scrub(data, aggressive, report, path)
    out = json.dumps(data, separators=(",", ":"), ensure_ascii=False)
    report.add(path, "redact-json")
    return out.encode("utf-8") if was_bytes else out


def rule_for(key, aggressive):
    if key in CONTENT_KEYS:
        return CONTENT_KEYS[key]
    if aggressive and key in LABEL_KEYS:
        return LABEL_KEYS[key]
    for prefix, action in PREFIX_CONTENT:
        if key.startswith(prefix):
            return action  # may be None => recurse
    return "recurse"


def scrub(obj, aggressive, report, path):
    """Walk obj in place, applying rules by key name. Returns obj."""
    if isinstance(obj, dict):
        for key in list(obj.keys()):
            action = rule_for(str(key), aggressive)
            value = obj[key]
            child = path + [str(key)]

            # Preserve trigger/highlight color params (parameter encodes colors).
            if (key == "parameter" and action == REDACT_V and
                    isinstance(obj.get("action"), str) and
                    obj["action"] in HIGHLIGHT_ACTIONS):
                continue

            if action == REMOVE:
                del obj[key]
                report.add(child, "remove")
            elif action == JSON_V:
                obj[key] = redact_json(value, aggressive, report, child)
            elif action == REDACT_V:
                obj[key] = redact_value(value, report, child)
                report.add(child, "redact")
            else:
                # "recurse" or None: descend to find nested matches.
                scrub(value, aggressive, report, child)
    elif isinstance(obj, list):
        for i, item in enumerate(obj):
            scrub(item, aggressive, report, path + [str(i)])
    return obj


def load_plist(path):
    with open(path, "rb") as f:
        raw = f.read()
    fmt = plistlib.FMT_BINARY if raw[:8] == b"bplist00" else plistlib.FMT_XML
    return plistlib.loads(raw), fmt


def sanitize_file(in_path, out_path, aggressive, dry_run):
    data, fmt = load_plist(in_path)
    report = Report()
    scrub(data, aggressive, report, [])

    print(f"\n{in_path}")
    print(f"  format: {'binary' if fmt == plistlib.FMT_BINARY else 'xml'}")
    if not report.entries:
        print("  nothing to redact")
    else:
        for top, count in sorted(report.summary().items(), key=lambda kv: -kv[1]):
            print(f"  {count:5d}  {top}")
        print(f"  {'-' * 5}")
        print(f"  {len(report.entries):5d}  total redactions")

    if dry_run:
        print("  (dry run; no file written)")
        return

    with open(out_path, "wb") as f:
        plistlib.dump(data, f, fmt=fmt)
    print(f"  wrote: {out_path}")


def private_sibling(main_path):
    d = os.path.dirname(os.path.abspath(main_path))
    base = os.path.basename(main_path)
    if base == "com.googlecode.iterm2.plist":
        cand = os.path.join(d, "com.googlecode.iterm2.private.plist")
        if os.path.exists(cand):
            return cand
    return None


def default_output(path):
    root, ext = os.path.splitext(path)
    return root + ".sanitized" + ext


def main(argv):
    ap = argparse.ArgumentParser(
        description="Surgically redact private info from an iTerm2 plist.")
    ap.add_argument("input", help="path to com.googlecode.iterm2.plist")
    ap.add_argument("-o", "--output",
                    help="output path (default: INPUT.sanitized.plist)")
    ap.add_argument("--in-place", action="store_true",
                    help="overwrite the input file")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would be redacted; write nothing")
    ap.add_argument("--aggressive", action="store_true",
                    help="also redact labels (profile names, tags, titles, "
                         "model names, installation id)")
    ap.add_argument("--no-private", action="store_true",
                    help="do not also sanitize the sibling private plist")
    args = ap.parse_args(argv)

    if not os.path.exists(args.input):
        ap.error(f"no such file: {args.input}")
    if args.in_place and args.output:
        ap.error("--in-place and --output are mutually exclusive")

    targets = [args.input]
    if not args.no_private:
        sib = private_sibling(args.input)
        if sib:
            targets.append(sib)

    for path in targets:
        if args.in_place:
            out = path
        elif args.output and path == args.input:
            out = args.output
        else:
            out = default_output(path)
        try:
            sanitize_file(path, out, args.aggressive, args.dry_run)
        except Exception as e:  # noqa: BLE001 - report and continue
            print(f"\n{path}\n  ERROR: {e}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
