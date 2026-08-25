#!/usr/bin/env python3
"""Hide a session's custom tab color after a period without terminal output.

This is a userland replacement for a proposed built-in advanced setting. Once a
session with a custom tab color has produced nothing for TIMEOUT_HOURS hours,
its tab color is turned off (without erasing the configured color). When output
resumes, the color comes back.

Install by copying this file into
    ~/Library/Application Support/iTerm2/Scripts/AutoLaunch/
so it starts with iTerm2, or run it once from
    Scripts > Manage > ... in iTerm2. It needs the Python API enabled
(Preferences > General > Magic > Enable Python API).

Configuration: edit the TIMEOUT_HOURS and POLL_INTERVAL_SECONDS globals below.

How it stays cheap: iTerm2 has no "tab color changed" event to subscribe to, so
the script does a periodic scan (three profile keys per session) to learn which
sessions have a custom tab color. It subscribes to screen-update notifications
ONLY for those colored sessions, so idle plain sessions generate no notification
traffic at all. Because the timeout is measured in hours, the scan runs rarely,
and its per-session profile reads are spaced out (SCAN_STAGGER_SECONDS) rather
than fired back-to-back, so the scan never hits iTerm2's main queue in a burst.

Known limitations (things the native version does not have):
  - "Output" is inferred from screen-change notifications, which also fire on
    selection changes and blinking text (but not a plain blinking cursor). It
    is a close proxy for terminal output, not an exact one.
  - The script only acts while it is running. If it is restarted while some
    colors are hidden, it has no record that it hid them, so those sessions
    stay colorless until you re-enable their tab color or the session ends.
  - Color changes are noticed on the next scan, so gaining or losing a custom
    tab color takes up to POLL_INTERVAL_SECONDS to take effect.
"""

import asyncio
import time

import iterm2
import iterm2.api_pb2
import iterm2.notifications
import iterm2.profile
import iterm2.rpc

# Hours of inactivity before a tab color is hidden. Set to 0 to disable.
# (For a quick test, try 5 seconds: TIMEOUT_HOURS = 5 / 3600.)
TIMEOUT_HOURS = 2.0
# How often, in seconds, to scan for colored sessions and expire idle ones.
# The timeout is in hours, so this can be coarse; once a minute is plenty.
POLL_INTERVAL_SECONDS = 60.0
# Pause between individual per-session profile reads within one scan. Reading
# every session's profile back-to-back hits iTerm2's main queue in a burst and
# causes a visible hitch, so the reads are spread out by this much instead.
SCAN_STAGGER_SECONDS = 0.1

# A session can use up to three "use tab color" flags depending on whether it
# has separate light/dark colors. Each entry is (profile key, Profile getter,
# LocalWriteOnlyProfile setter) so we can read just these keys and hide/restore
# exactly the flags the user had turned on, in either color mode. We never touch
# the color value itself, only whether it is used, so it is preserved untouched.
USE_TAB_COLOR_FLAGS = [
    ("Use Tab Color", "use_tab_color", "set_use_tab_color"),
    ("Use Tab Color (Light)", "use_tab_color_light", "set_use_tab_color_light"),
    ("Use Tab Color (Dark)", "use_tab_color_dark", "set_use_tab_color_dark"),
]
USE_TAB_COLOR_KEYS = [key for key, _getter, _setter in USE_TAB_COLOR_FLAGS]


def all_sessions(app):
    for window in app.windows:
        for tab in window.tabs:
            for session in tab.all_sessions:
                yield session
    for session in app.buried_sessions:
        yield session


async def active_use_tab_color_setters(session):
    """Return the setters for whichever "use tab color" flags are currently on.

    Fetches only the three flag keys rather than the entire profile.
    """
    response = await iterm2.rpc.async_get_profile(
        session.connection, session.session_id, keys=USE_TAB_COLOR_KEYS)
    status = response.get_profile_property_response.status
    if status != iterm2.api_pb2.GetProfilePropertyResponse.Status.Value("OK"):
        return []
    profile = iterm2.profile.Profile(
        session.session_id,
        session.connection,
        response.get_profile_property_response.properties)
    return [setter for _key, getter, setter in USE_TAB_COLOR_FLAGS
            if getattr(profile, getter)]


async def set_use_tab_color(session, setters, value):
    """Turn the given "use tab color" flags on or off on a session's local
    profile, leaving the color value itself untouched."""
    change = iterm2.LocalWriteOnlyProfile()
    for setter in setters:
        getattr(change, setter)(value)
    await session.async_set_profile_properties(change)


async def start_watching(session, on_update, watched):
    """Subscribe to screen updates for one session so we can time its output."""
    token = await iterm2.notifications.async_subscribe_to_screen_update_notification(
        session.connection, on_update, session.session_id)
    watched[session.session_id] = token


async def stop_watching(connection, sid, watched):
    token = watched.pop(sid, None)
    if token is None:
        return
    try:
        await iterm2.notifications.async_unsubscribe(connection, token)
    except iterm2.notifications.SubscriptionException:
        pass


async def restore_tab_color(app, sid, hidden):
    """Turn the tab color back on for a session we previously hid."""
    setters = hidden.pop(sid, None)
    if not setters:
        return
    session = app.get_session_by_id(sid)
    if session is None:
        return
    await set_use_tab_color(session, setters, True)


async def reconcile(app, connection, on_update, watched, last_activity, hidden,
                    timeout_seconds):
    """Watch colored sessions, unwatch the rest, and expire idle ones.

    Sessions with no custom tab color are not watched at all, so they produce no
    screen-update traffic. We learn which sessions are colored by reading three
    profile keys each; that is the only per-poll network cost, and those reads
    are spaced out so a scan never floods iTerm2's main queue.
    """
    live = set()
    # Snapshot first so that pausing between reads (below) can't trip over the
    # app's live-updating window/session model mid-iteration.
    sessions = list(all_sessions(app))
    for index, session in enumerate(sessions):
        if index > 0:
            await asyncio.sleep(SCAN_STAGGER_SECONDS)
        sid = session.session_id
        live.add(sid)
        setters = await active_use_tab_color_setters(session)
        # A session we hid reads as "no color" (we turned the flag off) but must
        # keep being watched so resumed output can restore it.
        if not setters and sid not in hidden:
            await stop_watching(connection, sid, watched)
            last_activity.pop(sid, None)
            continue
        if sid not in watched:
            await start_watching(session, on_update, watched)
            last_activity.setdefault(sid, time.monotonic())
        if setters and sid not in hidden:
            idle = time.monotonic() - last_activity.get(sid, time.monotonic())
            if idle >= timeout_seconds:
                await set_use_tab_color(session, setters, False)
                hidden[sid] = setters

    for sid in list(watched.keys()):
        if sid not in live:
            await stop_watching(connection, sid, watched)
            last_activity.pop(sid, None)
            hidden.pop(sid, None)


async def main(connection):
    app = await iterm2.async_get_app(connection)
    timeout_seconds = TIMEOUT_HOURS * 3600.0

    if timeout_seconds <= 0:
        # Nothing to do, but stay connected so editing TIMEOUT_HOURS and
        # relaunching is the only step needed to enable the feature.
        while True:
            await asyncio.sleep(3600)

    watched = {}        # session_id -> screen-update subscription token
    last_activity = {}  # session_id -> monotonic time of last output
    hidden = {}         # session_id -> setters we turned off

    async def on_update(_connection, notification):
        sid = notification.session
        last_activity[sid] = time.monotonic()
        if sid in hidden:
            await restore_tab_color(app, sid, hidden)

    while True:
        await reconcile(app, connection, on_update, watched, last_activity,
                        hidden, timeout_seconds)
        await asyncio.sleep(POLL_INTERVAL_SECONDS)


iterm2.run_forever(main, retry=True)
