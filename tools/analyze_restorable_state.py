#!/usr/bin/env python3
"""
Analyze iTerm2's restorable-state.sqlite database and print a hierarchy
of windows, tabs, and sessions with their titles.

Usage:
    python3 tools/analyze_restorable_state.py [path_to_database]

If no path is provided, uses the default location:
    ~/Library/Application Support/iTerm2/SavedState/restorable-state.sqlite
"""

import sqlite3
import sys
import os
import plistlib
import shutil
import tempfile
from pathlib import Path
from collections import defaultdict


def decode_nskeyed_archiver(data):
    """
    Decode NSKeyedArchiver data (binary plist format).
    Returns a dictionary of decoded values.
    """
    if not data or len(data) == 0:
        return {}

    try:
        # NSKeyedArchiver uses binary plist format
        plist = plistlib.loads(data)

        # NSKeyedArchiver stores data in a specific structure
        if not isinstance(plist, dict) or '$archiver' not in plist:
            # Not NSKeyedArchiver format, try to return as-is
            return plist if isinstance(plist, dict) else {}

        # Extract the objects array
        objects = plist.get('$objects', [])
        if not objects:
            return {}

        # Resolve references and build the dictionary
        return decode_keyed_archive_objects(objects, plist.get('$top', {}))
    except Exception as e:
        # If decoding fails, return empty dict
        return {}


def decode_keyed_archive_objects(objects, top):
    """
    Decode the $objects array from NSKeyedArchiver format.
    This handles the reference-based structure used by NSKeyedArchiver.
    """
    def resolve(obj):
        """Recursively resolve UID references."""
        if isinstance(obj, plistlib.UID):
            idx = obj.data
            if idx < len(objects):
                return resolve(objects[idx])
            return None
        elif isinstance(obj, dict):
            # Check if this is an NS.keys/NS.objects dictionary
            if 'NS.keys' in obj and 'NS.objects' in obj:
                keys = resolve(obj['NS.keys'])
                values = resolve(obj['NS.objects'])
                if isinstance(keys, list) and isinstance(values, list):
                    result = {}
                    for k, v in zip(keys, values):
                        if isinstance(k, str):
                            result[k] = resolve(v)
                    return result
            # Check if this is an NS.objects array
            elif 'NS.objects' in obj and 'NS.keys' not in obj:
                arr = obj['NS.objects']
                if isinstance(arr, list):
                    return [resolve(item) for item in arr]
            # Check for NS.data (raw data)
            elif 'NS.data' in obj:
                return obj['NS.data']
            # Check for NS.string
            elif 'NS.string' in obj:
                return obj['NS.string']
            # Regular dict - resolve all values
            else:
                return {k: resolve(v) for k, v in obj.items() if not k.startswith('$')}
        elif isinstance(obj, list):
            return [resolve(item) for item in obj]
        elif obj == '$null':
            return None
        else:
            return obj

    # Start from $top and resolve
    if 'root' in top:
        return resolve(top['root'])

    # Try to resolve the first non-null object as root
    result = {}
    for key, value in top.items():
        resolved = resolve(value)
        if resolved is not None:
            result[key] = resolved
    return result


def load_database(db_path):
    """Load the SQLite database and return all nodes."""
    # Try to open directly first
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='Node'")
        if cursor.fetchone():
            cursor.execute("SELECT key, identifier, parent, rowid, data FROM Node")
            rows = cursor.fetchall()
            conn.close()
            return rows
        conn.close()
    except sqlite3.OperationalError as e:
        if "locked" in str(e).lower():
            print(f"Database is locked (iTerm2 is likely running).")
            print("Creating a temporary copy to analyze...")

            # Copy to temp file
            with tempfile.NamedTemporaryFile(suffix='.sqlite', delete=False) as tmp:
                temp_path = tmp.name

            try:
                shutil.copy2(db_path, temp_path)
                conn = sqlite3.connect(temp_path)
                cursor = conn.cursor()

                cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='Node'")
                if not cursor.fetchone():
                    print(f"Error: No 'Node' table found in {db_path}")
                    print("This may not be a valid iTerm2 restorable state database.")
                    sys.exit(1)

                cursor.execute("SELECT key, identifier, parent, rowid, data FROM Node")
                rows = cursor.fetchall()
                conn.close()
                os.unlink(temp_path)
                return rows
            except Exception as e2:
                if os.path.exists(temp_path):
                    os.unlink(temp_path)
                raise e2
        else:
            raise

    # Fallback: original behavior
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='Node'")
    if not cursor.fetchone():
        print(f"Error: No 'Node' table found in {db_path}")
        print("This may not be a valid iTerm2 restorable state database.")
        sys.exit(1)

    cursor.execute("SELECT key, identifier, parent, rowid, data FROM Node")
    rows = cursor.fetchall()
    conn.close()

    return rows


def build_tree(rows):
    """Build a tree structure from the database rows."""
    nodes = {}
    children_map = defaultdict(list)
    root_id = None

    for key, identifier, parent, rowid, data in rows:
        pod = decode_nskeyed_archiver(data) if data else {}

        nodes[rowid] = {
            'key': key,
            'identifier': identifier,
            'parent': parent,
            'rowid': rowid,
            'pod': pod,
            'children': []
        }

        if parent == 0 and key == '':
            root_id = rowid
        else:
            children_map[parent].append(rowid)

    # Link children
    for parent_id, child_ids in children_map.items():
        if parent_id in nodes:
            nodes[parent_id]['children'] = [nodes[cid] for cid in child_ids if cid in nodes]

    return nodes.get(root_id) if root_id else None


def get_pod_value(pod, key, default=None):
    """Safely get a value from a POD dictionary."""
    if isinstance(pod, dict):
        return pod.get(key, default)
    return default


def find_children_by_key(node, key):
    """Find all direct children with a specific key."""
    if not node:
        return []
    return [c for c in node.get('children', []) if c.get('key') == key]


def find_child_by_key(node, key):
    """Find the first direct child with a specific key."""
    children = find_children_by_key(node, key)
    return children[0] if children else None


def extract_session_info(session_node):
    """Extract session information from a session node."""
    pod = session_node.get('pod', {})

    # Try to get session name from various sources
    session_name = None

    # Check Name Controller State first (contains the actual displayed name)
    name_controller = get_pod_value(pod, 'Name Controller State')
    if isinstance(name_controller, dict):
        # The name controller has various name sources
        session_name = name_controller.get('presentationSessionTitle')
        if not session_name:
            session_name = name_controller.get('effectiveSessionTitle')

    # Fallback to direct session name
    if not session_name:
        session_name = get_pod_value(pod, 'Session Name')

    # Get other info
    guid = get_pod_value(pod, 'Session GUID', session_node.get('identifier', 'unknown'))
    working_dir = get_pod_value(pod, 'Working Directory', '')
    columns = get_pod_value(pod, 'Columns', 0)
    rows = get_pod_value(pod, 'Rows', 0)

    # Check for tmux
    tmux_pane = get_pod_value(pod, 'Tmux Pane')
    is_tmux = tmux_pane is not None

    # Check if contents exist
    has_contents = 'Contents' in pod or find_child_by_key(session_node, 'Contents') is not None

    # Get profile/bookmark info
    bookmark = get_pod_value(pod, 'Bookmark')
    profile_name = None
    if isinstance(bookmark, dict):
        profile_name = bookmark.get('Name')

    return {
        'name': session_name,
        'guid': guid,
        'working_dir': working_dir,
        'columns': columns,
        'rows': rows,
        'is_tmux': is_tmux,
        'has_contents': has_contents,
        'profile_name': profile_name,
    }


def extract_sessions_from_view(view_node, sessions, debug=False):
    """Recursively extract sessions from a view hierarchy."""
    pod = view_node.get('pod', {})
    view_type = get_pod_value(pod, 'View Type', '')

    if debug:
        print(f"      View key={view_node.get('key')} type={view_type}")
        print(f"      View children: {[c.get('key') for c in view_node.get('children', [])]}")

    if view_type == 'SessionView':
        # This is a session view - look for Session child
        session_child = find_child_by_key(view_node, 'Session')
        if session_child:
            sessions.append(extract_session_info(session_child))
        # Also check under __array
        array_node = find_child_by_key(view_node, '__array')
        if array_node:
            for child in array_node.get('children', []):
                if child.get('key') == 'Session' or 'Session GUID' in child.get('pod', {}):
                    sessions.append(extract_session_info(child))

    elif view_type == 'Splitter':
        # This is a splitter - recurse into subviews
        # First try explicit Subviews key
        subviews = find_children_by_key(view_node, 'Subviews')
        for subview_container in subviews:
            for subview in subview_container.get('children', []):
                extract_sessions_from_view(subview, sessions, debug)

        # Also check __array which may contain subviews
        array_node = find_child_by_key(view_node, '__array')
        if array_node:
            for child in array_node.get('children', []):
                child_pod = child.get('pod', {})
                # If child has View Type, recurse
                if 'View Type' in child_pod:
                    extract_sessions_from_view(child, sessions, debug)
                # If child looks like a session
                elif 'Session GUID' in child_pod:
                    sessions.append(extract_session_info(child))

    # Also check direct Session children (for simpler layouts)
    for child in view_node.get('children', []):
        if child.get('key') == 'Session':
            sessions.append(extract_session_info(child))

    # Recurse into any __array children that might contain sessions
    for child in view_node.get('children', []):
        child_key = child.get('key', '')
        if child_key == '__array':
            for subchild in child.get('children', []):
                subchild_pod = subchild.get('pod', {})
                if 'View Type' in subchild_pod:
                    extract_sessions_from_view(subchild, sessions, debug)
                elif 'Session GUID' in subchild_pod:
                    sessions.append(extract_session_info(subchild))


def extract_tab_info(tab_node, debug=False):
    """Extract tab information from a tab node."""
    pod = tab_node.get('pod', {})

    if debug:
        print(f"    Tab node key={tab_node.get('key')} id={tab_node.get('identifier')}")
        print(f"    Tab children: {[c.get('key') for c in tab_node.get('children', [])]}")
        print(f"    Tab POD keys: {list(pod.keys())[:10]}")

    # Get tab title
    title_override = get_pod_value(pod, 'Title Override')
    is_active = get_pod_value(pod, 'Is Active', False)
    tab_guid = get_pod_value(pod, 'Tab GUID', tab_node.get('identifier', 'unknown'))

    # Extract sessions from the tab's view hierarchy
    sessions = []

    # Look for Root view
    root = find_child_by_key(tab_node, 'Root')
    if root:
        if debug:
            print(f"    Found Root with children: {[c.get('key') for c in root.get('children', [])]}")
        extract_sessions_from_view(root, sessions, debug)

    # Also check for direct Session children
    session_children = find_children_by_key(tab_node, 'Session')
    for session_child in session_children:
        sessions.append(extract_session_info(session_child))

    # Check for sessions under __array
    if not sessions:
        for child in tab_node.get('children', []):
            if child.get('key') == 'Session' or 'Session GUID' in child.get('pod', {}):
                sessions.append(extract_session_info(child))

    # Deduplicate sessions by GUID
    seen_guids = set()
    unique_sessions = []
    for session in sessions:
        guid = session.get('guid')
        if guid and guid not in seen_guids:
            seen_guids.add(guid)
            unique_sessions.append(session)

    return {
        'title': title_override,
        'is_active': is_active,
        'guid': tab_guid,
        'sessions': unique_sessions,
        'index': tab_node.get('identifier', '?'),
    }


def extract_window_info(window_node, debug=False):
    """Extract window information from a window node."""
    pod = window_node.get('pod', {})

    if debug:
        print(f"  Window node children: {[c.get('key') for c in window_node.get('children', [])]}")
        print(f"  Window POD keys: {list(pod.keys())[:10]}")

    # Get window title
    title_override = get_pod_value(pod, 'Title Override')
    window_guid = window_node.get('identifier', 'unknown')

    # Get window dimensions
    width = get_pod_value(pod, 'Width', 0)
    height = get_pod_value(pod, 'Height', 0)
    x_origin = get_pod_value(pod, 'X Origin', 0)
    y_origin = get_pod_value(pod, 'Y Origin', 0)

    # Check window state
    is_miniaturized = get_pod_value(pod, 'miniaturized', False)
    is_hotkey = get_pod_value(pod, 'Is Hotkey Window', False)
    selected_tab = get_pod_value(pod, 'Selected Tab Index', 0)

    # Extract tabs - try multiple approaches
    tabs = []

    # Approach 1: Direct 'Tabs' child
    tabs_container = find_child_by_key(window_node, 'Tabs')
    if tabs_container:
        if debug:
            print(f"  Found Tabs container with {len(tabs_container.get('children', []))} children")
        for tab_child in tabs_container.get('children', []):
            tabs.append(extract_tab_info(tab_child, debug))

    # Approach 2: Tabs might be nested under __array
    if not tabs:
        array_node = find_child_by_key(window_node, '__array')
        if array_node:
            if debug:
                print(f"  Found __array with {len(array_node.get('children', []))} children")
            for child in array_node.get('children', []):
                # Check if this looks like a tab
                child_pod = child.get('pod', {})
                if 'Root' in [c.get('key') for c in child.get('children', [])] or 'View Type' in child_pod:
                    tabs.append(extract_tab_info(child, debug))

    # Approach 3: Check children with numeric identifiers (tab indices)
    if not tabs:
        for child in window_node.get('children', []):
            child_key = child.get('key', '')
            child_id = child.get('identifier', '')
            # Tabs are often stored with numeric identifiers
            if child_id.isdigit() or child_key == 'Tabs':
                child_children = child.get('children', [])
                for cc in child_children:
                    if cc.get('identifier', '').isdigit():
                        tabs.append(extract_tab_info(cc, debug))

    # Sort tabs by index
    tabs.sort(key=lambda t: int(t['index']) if str(t['index']).isdigit() else 0)

    return {
        'title': title_override,
        'guid': window_guid,
        'width': width,
        'height': height,
        'x': x_origin,
        'y': y_origin,
        'is_miniaturized': is_miniaturized,
        'is_hotkey': is_hotkey,
        'selected_tab': selected_tab,
        'tabs': tabs,
    }


def debug_tree(node, depth=0, max_depth=4):
    """Print tree structure for debugging."""
    if depth > max_depth:
        return
    indent = "  " * depth
    key = node.get('key', '')
    identifier = node.get('identifier', '')
    pod_keys = list(node.get('pod', {}).keys())[:5]
    print(f"{indent}[{key}:{identifier}] pod_keys={pod_keys}")
    for child in node.get('children', [])[:5]:
        debug_tree(child, depth + 1, max_depth)


def print_hierarchy(root_node, debug=False):
    """Print the window/tab/session hierarchy."""
    if not root_node:
        print("No root node found in database.")
        return

    # Debug: show tree structure
    if debug:
        print("\nTree structure (first few levels):")
        debug_tree(root_node)
        print()

    # Find windows container - might be nested under 'app' or directly under root
    windows_container = find_child_by_key(root_node, 'windows')

    # If not found directly, try under 'app'
    if not windows_container:
        app_node = find_child_by_key(root_node, 'app')
        if app_node:
            windows_container = find_child_by_key(app_node, 'windows')

    # Also check for __array which might contain windows
    if not windows_container:
        array_node = find_child_by_key(root_node, '__array')
        if array_node:
            # Check if array contains window-like nodes
            for child in array_node.get('children', []):
                pod = child.get('pod', {})
                if 'Tabs' in pod or 'Selected Tab Index' in pod or find_child_by_key(child, 'Tabs'):
                    windows_container = array_node
                    break

    if not windows_container:
        print("No windows found in database.")
        print("\nRoot node structure:")
        debug_tree(root_node, max_depth=3)
        return

    windows = []
    for window_child in windows_container.get('children', []):
        windows.append(extract_window_info(window_child, debug))

    if not windows:
        print("No windows found in database.")
        return

    print(f"\n{'='*70}")
    print(f"iTerm2 Session Restoration Database Analysis")
    print(f"{'='*70}")
    print(f"\nTotal windows: {len(windows)}")

    total_tabs = sum(len(w['tabs']) for w in windows)
    total_sessions = sum(sum(len(t['sessions']) for t in w['tabs']) for w in windows)
    sessions_with_content = sum(
        sum(sum(1 for s in t['sessions'] if s['has_contents']) for t in w['tabs'])
        for w in windows
    )

    print(f"Total tabs: {total_tabs}")
    print(f"Total sessions: {total_sessions}")
    print(f"Sessions with content: {sessions_with_content}")
    print(f"Sessions without content: {total_sessions - sessions_with_content}")

    print(f"\n{'-'*70}")

    for i, window in enumerate(windows):
        window_title = window['title'] or f"Window {window['guid'][:8]}..."
        flags = []
        if window['is_miniaturized']:
            flags.append('minimized')
        if window['is_hotkey']:
            flags.append('hotkey')
        flags_str = f" [{', '.join(flags)}]" if flags else ""

        print(f"\n[Window {i+1}] {window_title}{flags_str}")
        print(f"  Position: ({window['x']:.0f}, {window['y']:.0f}), Size: {window['width']:.0f}x{window['height']:.0f}")
        print(f"  GUID: {window['guid']}")

        if not window['tabs']:
            print("  (no tabs)")
            continue

        for j, tab in enumerate(window['tabs']):
            is_selected = (j == window['selected_tab'])
            tab_title = tab['title'] or f"Tab {tab['index']}"
            active_marker = " *" if is_selected else ""

            print(f"\n  [Tab {j+1}]{active_marker} {tab_title}")

            if not tab['sessions']:
                print("    (no sessions)")
                continue

            for k, session in enumerate(tab['sessions']):
                session_name = session['name'] or session['profile_name'] or 'Unnamed'
                content_marker = "\u2713" if session['has_contents'] else "\u2717"
                tmux_marker = " [tmux]" if session['is_tmux'] else ""

                print(f"    [{content_marker}] {session_name}{tmux_marker}")
                print(f"        Size: {session['columns']}x{session['rows']}")
                if session['working_dir']:
                    print(f"        CWD: {session['working_dir']}")
                print(f"        GUID: {session['guid']}")

    print(f"\n{'='*70}")
    print("Legend: [\u2713] = has scrollback content, [\u2717] = no content (will be blank)")
    print("        * = active tab")
    print(f"{'='*70}\n")


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Analyze iTerm2's restorable-state.sqlite database"
    )
    parser.add_argument(
        'database',
        nargs='?',
        default=os.path.expanduser(
            "~/Library/Application Support/iTerm2/SavedState/restorable-state.sqlite"
        ),
        help="Path to the database file"
    )
    parser.add_argument(
        '--debug', '-d',
        action='store_true',
        help="Enable debug output showing tree structure"
    )

    args = parser.parse_args()
    db_path = args.database

    if not os.path.exists(db_path):
        print(f"Error: Database not found at {db_path}")
        print("\nUsage: python3 tools/analyze_restorable_state.py [path_to_database]")
        sys.exit(1)

    print(f"Analyzing: {db_path}")
    print(f"Database size: {os.path.getsize(db_path) / 1024 / 1024:.2f} MB")

    # Load and analyze
    rows = load_database(db_path)
    print(f"Total nodes in database: {len(rows)}")

    root = build_tree(rows)
    print_hierarchy(root, args.debug)


if __name__ == '__main__':
    main()
