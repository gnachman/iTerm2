#!/usr/bin/env python3
"""
Test script for iterm2.load_url built-in method.

Usage:
   python3 tests/load_url_test.py

The script will:
- Create a new browser tab
- Load example.com (should prompt for approval)
- Load another page on example.com (should NOT prompt - same domain)
- Load google.com (should prompt - different domain)
"""

import sys
import os

# Use the local iterm2 module from the repo
_script_dir = os.path.dirname(os.path.abspath(__file__))
_iterm2_module_path = os.path.join(_script_dir, '..', 'api', 'library', 'python', 'iterm2')
sys.path.insert(0, _iterm2_module_path)

import iterm2
import asyncio


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_window

    if not window:
        print("No current window")
        return

    # Create a browser tab using profile customizations
    print("Creating browser session...")
    profile = iterm2.LocalWriteOnlyProfile()
    profile.set_use_custom_command("Browser")

    tab = await window.async_create_tab(profile_customizations=profile)
    session = tab.current_session
    print(f"Created browser session: {session.session_id}")

    # Give the browser a moment to initialize
    await asyncio.sleep(1)

    # Test 1: Load example.com (should prompt)
    print("\n--- Test 1: Loading https://example.com ---")
    print("(You should see a permission dialog)")
    try:
        await session.async_load_url("https://example.com")
        print("Success: example.com loaded")
    except iterm2.rpc.RPCException as e:
        print(f"Error: {e}")

    await asyncio.sleep(2)

    # Test 2: Load another page on same domain (should NOT prompt)
    print("\n--- Test 2: Loading https://example.com/about ---")
    print("(Should NOT prompt - same domain already approved)")
    try:
        await session.async_load_url("https://example.com/about")
        print("Success: example.com/about loaded without prompting")
    except iterm2.rpc.RPCException as e:
        print(f"Error: {e}")

    await asyncio.sleep(2)

    # Test 3: Load different domain (should prompt)
    print("\n--- Test 3: Loading https://www.google.com ---")
    print("(You should see another permission dialog)")
    try:
        await session.async_load_url("https://www.google.com")
        print("Success: google.com loaded")
    except iterm2.rpc.RPCException as e:
        print(f"Error: {e}")

    print("\n--- Tests complete ---")


iterm2.run_until_complete(main)
