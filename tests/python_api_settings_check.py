#!/usr/bin/env python3
"""Checks the Python API's settings coverage against a running iTerm2.

Run it against a development build so it can't disturb your main instance:

    make run   # in another terminal
    IT2_SUITE="$(basename "$PWD")" \
    IT2_APP_PATH="$PWD/Build/Development/iTerm2.app" \
    PYTHONPATH=api/library/python/iterm2 \
    python3 tests/python_api_settings_check.py

It reads every PreferenceKey and every Profile property and reports any that
come back null even though iTerm2 defines a non-null default for that key,
which usually means the key string is misspelled. Then it round-trips a sample
of setters (including enum-valued ones through the async path) and restores
the original values.
"""

import os
import re
import sys
from pathlib import Path

import iterm2

REPO = Path(__file__).resolve().parent.parent


def read(path):
    return (REPO / path).read_text()


def defaults_from(path, key_prefix):
    """Returns {key string: has non-null default} parsed from a defaults map."""
    source = read(path)
    constants = {}
    for header in ("sources/Settings/iTermPreferences.m",
                   "sources/Settings/Profiles/ITAddressBookMgr.h"):
        text = read(header)
        constants.update(re.findall(r'NSString \*const (kPreference\w+)\s*=\s*@"([^"]*)"', text))
        constants.update(re.findall(r'^#define (KEY_\w+)\s+@"([^"]*)"', text, re.MULTILINE))
    start = source.index("+ (NSDictionary *)defaultValueMap")
    end = source.index("\n}\n", start)
    result = {}
    for name, value in re.findall(r"^\s*(" + key_prefix + r"\w+)\s*:\s*(.+?),?\s*(?://.*)?$",
                                  source[start:end], re.MULTILINE):
        if name in constants:
            result.setdefault(constants[name], "NSNull" not in value)
    return result


def report(title, problems):
    print(f"{title}: {'OK' if not problems else f'{len(problems)} problem(s)'}")
    for problem in problems:
        print(f"    {problem}")
    return not problems


async def check_global_reads(connection):
    defaults = defaults_from("sources/Settings/iTermPreferences.m", "kPreference")
    problems = []
    for key in iterm2.PreferenceKey:
        value = await iterm2.async_get_preference(connection, key)
        if value is None and defaults.get(key.value, False):
            problems.append(f"{key.name} ({key.value!r}) is null but has a default")
        elif key.value not in defaults and value is None:
            # Keys without a default (like Snippets) are fine only if the app knows them.
            source = read("sources/Settings/iTermPreferences.m")
            if f'@"{key.value}"' not in source:
                problems.append(f"{key.name} ({key.value!r}) is not a key iTerm2 defines")
    return report(f"Read all {len(iterm2.PreferenceKey)} PreferenceKeys", problems)


async def check_global_writes(connection):
    samples = {
        iterm2.PreferenceKey.WORD_SELECTION_MODE: 1,
        iterm2.PreferenceKey.TMUX_PAUSE_MODE_AGE_LIMIT: 77,
        iterm2.PreferenceKey.QUICK_LOOK_HOVER_DOMAIN_ALLOWLIST: ["example.com"],
        iterm2.PreferenceKey.AI_PERMISSION_RUN_COMMANDS: 2,
        iterm2.PreferenceKey.TAB_BAR_POSITION: 3,
    }
    problems = []
    for key, value in samples.items():
        original = await iterm2.async_get_preference(connection, key)
        try:
            await iterm2.async_set_preference(connection, key, value)
            actual = await iterm2.async_get_preference(connection, key)
            if actual != value:
                problems.append(f"{key.name}: set {value!r}, read back {actual!r}")
        finally:
            await iterm2.async_set_preference(connection, key, original)
    return report(f"Round-trip {len(samples)} PreferenceKeys", problems)


def profile_properties():
    """Returns {python property name: key} for every generated Profile getter."""
    source = read("api/library/python/iterm2/iterm2/profile.py")
    profile_class = source[source.index("class Profile(WriteOnlyProfile):"):]
    profile_class = profile_class[:profile_class.index("\nclass ")]
    result = {}
    for block in profile_class.split("    @property\n")[1:]:
        name = re.match(r"\s*def (\w+)\(self\)", block)
        body = block.split("\n    def ")[0]
        key = re.search(r'self\.(?:_simple_get|_get_optional_bool|get_color_with_key)\(\s*"([^"]+)"', body)
        if name and key:
            result[name.group(1)] = key.group(1)
    return result


async def check_profile_reads(session):
    profile = await session.async_get_profile()
    defaults = defaults_from("sources/Settings/iTermProfilePreferences.m", "KEY_")
    problems = []
    properties = profile_properties()
    for name, key in properties.items():
        value = getattr(profile, name)
        base_key = re.sub(r" \((Light|Dark)\)$", "", key)
        if value is None and defaults.get(key, defaults.get(base_key, False)):
            problems.append(f"{name} ({key!r}) is null but has a default")
    return report(f"Read all {len(properties)} Profile properties", problems)


def rgb(color_dict):
    return tuple(round(color_dict[f"{c} Component"] * 255) for c in ("Red", "Green", "Blue"))


async def check_profile_writes(session):
    profile = await session.async_get_profile()
    original = {
        "Cursor Type": profile.cursor_type,
        "Timestamps Style": profile.timestamps_style,
        "Cursor Blink Fade In Curve": profile.cursor_blink_fade_in_curve,
        "Use Active Pane Border": profile.use_active_pane_border,
        "Tags": profile.tags,
        "Match Background Color (Dark)": profile.match_color_dark,
    }
    problems = []
    try:
        # Async setters, which used to raise TypeError for enums.
        await profile.async_set_cursor_type(iterm2.CursorType.CURSOR_TYPE_BOX)
        await profile.async_set_timestamps_style(iterm2.TimestampsStyle.ADJACENT)
        await profile.async_set_use_active_pane_border(True)
        # LocalWriteOnlyProfile path.
        change = iterm2.LocalWriteOnlyProfile()
        change.set_cursor_blink_fade_in_curve(iterm2.CursorBlinkFadeCurve.LINEAR)
        change.set_tags(["api-check"])
        change.set_match_color_dark(iterm2.Color(10, 20, 30))
        await session.async_set_profile_properties(change)

        after = await session.async_get_profile()
        expected = {
            "cursor_type": 2,
            "timestamps_style": 3,
            "use_active_pane_border": True,
            "cursor_blink_fade_in_curve": 0,
            "tags": ["api-check"],
        }
        for name, value in expected.items():
            if getattr(after, name) != value:
                problems.append(f"{name}: expected {value!r}, read back {getattr(after, name)!r}")
        color = after.match_color_dark
        if color is None or (round(color.red), round(color.green), round(color.blue)) != (10, 20, 30):
            problems.append(f"match_color_dark: read back {color!r}")
    finally:
        # The server rejects null without reporting an error, so restore an
        # absent value with its empty equivalent and verify the restore.
        if original["Tags"] is None:
            original["Tags"] = []
        restore = iterm2.LocalWriteOnlyProfile()
        for key, value in original.items():
            if value is None:
                problems.append(f"{key}: was null, which can't be restored; reset it by hand")
            elif isinstance(value, iterm2.Color):
                restore._color_set(key, value)
            else:
                restore._simple_set(key, value)
        await session.async_set_profile_properties(restore)
        restored = (await session.async_get_profile()).all_properties
        for key, value in original.items():
            if value is None:
                continue
            actual = restored.get(key)
            if isinstance(value, iterm2.Color):
                same = actual is not None and rgb(actual) == rgb(value.get_dict())
            else:
                same = actual == value
            if not same:
                problems.append(f"{key}: restore failed, now {actual!r} instead of {value!r}")
    return report("Round-trip Profile setters", problems)


async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_terminal_window.current_tab.current_session
    results = [
        await check_global_reads(connection),
        await check_global_writes(connection),
        await check_profile_reads(session),
        await check_profile_writes(session),
    ]
    if not all(results):
        sys.exit(1)


if __name__ == "__main__":
    if not os.environ.get("IT2_SUITE"):
        sys.exit("Set IT2_SUITE (and IT2_APP_PATH) so this doesn't modify your main iTerm2.")
    iterm2.run_until_complete(main)
