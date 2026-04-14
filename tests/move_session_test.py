#!/usr/bin/env python3

import iterm2
import sys

async def list_windows(app):
    print("\n=== Windows ===")
    for i, window in enumerate(app.windows):
        tab_count = len(window.tabs)
        print(f"  [{i}] Window {window.window_id} ({tab_count} tab{'s' if tab_count != 1 else ''})")
        for j, tab in enumerate(window.tabs):
            session_count = len(tab.sessions)
            active = " *" if tab.tab_id == window.selected_tab_id else ""
            print(f"      [{j}] Tab {tab.tab_id} ({session_count} session{'s' if session_count != 1 else ''}){active}")
            for k, session in enumerate(tab.sessions):
                name = session.name or "(unnamed)"
                active_s = " *" if session.session_id == tab.active_session_id else ""
                print(f"          [{k}] Session {session.session_id} - {name}{active_s}")

def find_session(app, window_idx, tab_idx, session_idx):
    try:
        window = app.windows[window_idx]
        tab = window.tabs[tab_idx]
        session = tab.sessions[session_idx]
        return session
    except IndexError:
        print("Invalid indices.")
        return None

def find_window(app, window_idx):
    try:
        return app.windows[window_idx]
    except IndexError:
        print("Invalid window index.")
        return None

async def do_move_to_new_tab(app):
    await list_windows(app)
    print("\n--- Move Session to New Tab ---")
    try:
        parts = input("Source session [window tab session]: ").split()
        wi, ti, si = int(parts[0]), int(parts[1]), int(parts[2])
    except (ValueError, IndexError):
        print("Need three integers: window_index tab_index session_index")
        return

    session = find_session(app, wi, ti, si)
    if not session:
        return

    dest_input = input("Destination window index (enter for same window): ").strip()
    dest_window = None
    if dest_input:
        dest_window = find_window(app, int(dest_input))
        if not dest_window:
            return

    idx_input = input("Tab index (enter for default): ").strip()
    tab_index = int(idx_input) if idx_input else None

    print(f"Moving session {session.session_id} to new tab"
          f"{' in window ' + dest_window.window_id if dest_window else ''}"
          f"{' at index ' + str(tab_index) if tab_index is not None else ''}...")
    try:
        tab_id = await session.async_move_to_new_tab(
            window=dest_window,
            tab_index=tab_index)
        print(f"Success! New tab ID: {tab_id}")
    except Exception as e:
        print(f"Error: {e}")

async def do_move_to_new_window(app):
    await list_windows(app)
    print("\n--- Move Session to New Window ---")
    try:
        parts = input("Source session [window tab session]: ").split()
        wi, ti, si = int(parts[0]), int(parts[1]), int(parts[2])
    except (ValueError, IndexError):
        print("Need three integers: window_index tab_index session_index")
        return

    session = find_session(app, wi, ti, si)
    if not session:
        return

    print(f"Moving session {session.session_id} to new window...")
    try:
        window_id = await session.async_move_to_new_window()
        if window_id:
            print(f"Success! New window ID: {window_id}")
        else:
            print("Returned None (tmux session moved asynchronously, or failure)")
    except Exception as e:
        print(f"Error: {e}")

async def do_move_to_split(app):
    await list_windows(app)
    print("\n--- Move Session to Split Pane ---")
    try:
        parts = input("Source session [window tab session]: ").split()
        wi, ti, si = int(parts[0]), int(parts[1]), int(parts[2])
    except (ValueError, IndexError):
        print("Need three integers: window_index tab_index session_index")
        return

    session = find_session(app, wi, ti, si)
    if not session:
        return

    try:
        parts = input("Destination session [window tab session]: ").split()
        dwi, dti, dsi = int(parts[0]), int(parts[1]), int(parts[2])
    except (ValueError, IndexError):
        print("Need three integers: window_index tab_index session_index")
        return

    dest = find_session(app, dwi, dti, dsi)
    if not dest:
        return

    direction = input("Direction (n/s/e/w) [default: e]: ").strip().lower() or "e"
    vertical = direction in ("e", "w")
    before = direction in ("n", "w")

    print(f"Moving session {session.session_id} to split {dest.session_id} ({direction})...")
    try:
        await app.async_move_session(session, dest, vertical, before)
        print("Success!")
    except Exception as e:
        print(f"Error: {e}")

async def main(connection):
    app = await iterm2.async_get_app(connection)

    while True:
        print("\n=== Move Session Test ===")
        print("  1. List windows/tabs/sessions")
        print("  2. Move session to new tab")
        print("  3. Move session to new window")
        print("  4. Move session to split pane (existing API)")
        print("  5. Refresh app state")
        print("  q. Quit")

        choice = input("\nChoice: ").strip().lower()
        if choice == "q":
            break
        elif choice == "1":
            await list_windows(app)
        elif choice == "2":
            await do_move_to_new_tab(app)
            app = await iterm2.async_get_app(connection)
        elif choice == "3":
            await do_move_to_new_window(app)
            app = await iterm2.async_get_app(connection)
        elif choice == "4":
            await do_move_to_split(app)
            app = await iterm2.async_get_app(connection)
        elif choice == "5":
            app = await iterm2.async_get_app(connection)
            print("Refreshed.")
        else:
            print("Unknown choice.")

iterm2.run_until_complete(main)
