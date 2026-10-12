#!/usr/bin/env python3
# Runs on the test VM, invoked over ssh by tools/vm/qa.sh. Edits the profiles in an iTerm2
# settings suite. Quit the app first (tools/vm/qa.sh quit): a running app overwrites them.
#
# Usage:
#   profiles.py SUITE list
#   profiles.py SUITE set [--name NAME] KEY=JSON...
#       Set keys on every profile, or only on the one named NAME.
#   profiles.py SUITE add NAME [KEY=JSON]...
#       Add a profile copied from the first one, with a new name and guid, then set keys.
#   profiles.py SUITE delete NAME
#
# Values are JSON, e.g.
#   profiles.py qa add Web 'Custom Command="Browser"' 'Initial URL="https://example.com"'
#   profiles.py qa set 'Show Status Bar=true'

import copy
import json
import plistlib
import subprocess
import sys
import uuid


def load(suite):
    out = subprocess.run(["defaults", "export", suite, "-"], capture_output=True, check=True).stdout
    return plistlib.loads(out)


def save(suite, data):
    subprocess.run(["defaults", "import", suite, "-"], input=plistlib.dumps(data), check=True)


def assignments(items):
    result = {}
    for item in items:
        key, sep, value = item.partition("=")
        if not sep:
            sys.exit(f"expected KEY=JSON, got {item}")
        result[key] = json.loads(value)
    return result


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__ or "see the comment at the top of profiles.py")
    suite, command, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
    data = load(suite)
    profiles = data.get("New Bookmarks", [])
    if not profiles:
        sys.exit(f"{suite} has no profiles yet. Launch the app once with this suite first.")
    if command == "list":
        for profile in profiles:
            print(profile.get("Name"), profile.get("Guid"))
        return
    if command == "set":
        name = None
        if rest[:1] == ["--name"]:
            name, rest = rest[1], rest[2:]
        values = assignments(rest)
        for profile in profiles:
            if name is None or profile.get("Name") == name:
                profile.update(values)
    elif command == "add":
        profile = copy.deepcopy(profiles[0])
        profile["Name"] = rest[0]
        profile["Guid"] = str(uuid.uuid4()).upper()
        profile.pop("Shortcut", None)
        profile.update(assignments(rest[1:]))
        profiles.append(profile)
    elif command == "delete":
        profiles = [p for p in profiles if p.get("Name") != rest[0]]
    else:
        sys.exit(f"unknown command {command}")
    data["New Bookmarks"] = profiles
    save(suite, data)
    print("Profiles:", ", ".join(p.get("Name", "") for p in profiles))


main()
