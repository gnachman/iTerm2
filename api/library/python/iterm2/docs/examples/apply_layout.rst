:orphan:

.. _apply_layout_example:

Move Sessions Between Tabs, Windows, and Split Panes
====================================================

This script registers three functions that demonstrate
:meth:`iterm2.App.async_apply_layout` — a single API call that reshapes one
or more tabs atomically. You can bind each function to a keystroke in
**Prefs > Keys** by selecting *Invoke Script Function* and using one of:

* ``swap_first_two_panes()``
* ``move_active_pane_to_next_tab()``
* ``move_active_pane_to_other_window()``

The shared idea: build a *spec* (a plain Python dict) describing the
tabs you want to reshape and any sessions/tabs/windows you want to
close, then hand it to ``app.async_apply_layout(spec)``. The whole
spec is validated up front and applied as a single transaction.

Spec basics
-----------

A spec has up to four optional fields:

.. code-block:: python

    {
        "tabs":           [{"tab_id": "...", "root": <node>}, ...],
        "close_sessions": ["<session-guid>", ...],
        "close_tabs":     ["<tab-id>", ...],
        "close_windows":  ["<window-guid>", ...],
    }

A ``<node>`` is either a leaf referring to a live session:

.. code-block:: python

    {"session_id": "<session-guid>"}

…or a splitter with at least two children:

.. code-block:: python

    {"vertical": True, "children": [<node>, <node>, ...]}

Sessions, tabs, and windows are referred to by the same identifiers
the rest of the Python API uses (``session.session_id``,
``tab.tab_id``, ``window.window_id``).

Example script
--------------

.. code-block:: python

    #!/usr/bin/env python3.7
    """
    Demo: move sessions between tabs, windows, and split panes via
    App.async_apply_layout.

    Registers three RPCs:
      swap_first_two_panes()
      move_active_pane_to_next_tab()
      move_active_pane_to_other_window()

    Bind any of these to a keystroke in Prefs > Keys via "Invoke Script
    Function".
    """

    import iterm2

    def leaf(session):
        """Build a leaf node for a session."""
        return {"session_id": session.session_id}

    def vrow(sessions):
        """Build a vertical-divider row of one or more sessions.

        A single session is returned as a leaf; two or more become a
        splitter. apply_layout requires splitters to have at least two
        children.
        """
        if len(sessions) == 1:
            return leaf(sessions[0])
        return {"vertical": True,
                "children": [leaf(s) for s in sessions]}

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        @iterm2.RPC
        async def swap_first_two_panes():
            """Swap the first two panes of the current tab."""
            tab = app.current_terminal_window.current_tab
            if len(tab.sessions) < 2:
                return
            a, b = tab.sessions[0], tab.sessions[1]
            spec = {
                "tabs": [{
                    "tab_id": tab.tab_id,
                    "root": {
                        "vertical": True,
                        "children": [leaf(b), leaf(a)] +
                                    [leaf(s) for s in tab.sessions[2:]],
                    },
                }],
            }
            await app.async_apply_layout(spec)
        await swap_first_two_panes.async_register(connection)

        @iterm2.RPC
        async def move_active_pane_to_next_tab():
            """Move the active pane from the current tab into the next
            tab in the same window."""
            window = app.current_terminal_window
            tabs = window.tabs
            if len(tabs) < 2:
                return
            src = window.current_tab
            i = next(idx for idx, t in enumerate(tabs)
                     if t.tab_id == src.tab_id)
            dst = tabs[(i + 1) % len(tabs)]
            active = src.current_session
            if active is None:
                return

            remaining = [s for s in src.sessions
                         if s.session_id != active.session_id]
            spec = {"tabs": []}
            if remaining:
                # Source tab keeps the other panes.
                spec["tabs"].append(
                    {"tab_id": src.tab_id, "root": vrow(remaining)})
            # Destination tab gains the moved pane on the right.
            spec["tabs"].append({
                "tab_id": dst.tab_id,
                "root": vrow(list(dst.sessions) + [active]),
            })
            # If the source tab loses every pane, apply_layout will
            # close it for us automatically — no need to list it in
            # close_tabs.
            await app.async_apply_layout(spec)
        await move_active_pane_to_next_tab.async_register(connection)

        @iterm2.RPC
        async def move_active_pane_to_other_window():
            """Move the active pane to the current tab of another
            window. Picks the next window in app.terminal_windows."""
            windows = app.terminal_windows
            if len(windows) < 2:
                return
            src_window = app.current_terminal_window
            i = next(idx for idx, w in enumerate(windows)
                     if w.window_id == src_window.window_id)
            dst_window = windows[(i + 1) % len(windows)]
            src_tab = src_window.current_tab
            dst_tab = dst_window.current_tab
            active = src_tab.current_session
            if active is None:
                return

            remaining = [s for s in src_tab.sessions
                         if s.session_id != active.session_id]
            spec = {"tabs": []}
            if remaining:
                spec["tabs"].append(
                    {"tab_id": src_tab.tab_id, "root": vrow(remaining)})
            spec["tabs"].append({
                "tab_id": dst_tab.tab_id,
                "root": vrow(list(dst_tab.sessions) + [active]),
            })
            await app.async_apply_layout(spec)
        await move_active_pane_to_other_window.async_register(connection)

    iterm2.run_forever(main)

Notes
-----

* **Atomicity.** The whole spec is validated before any mutation
  begins, so a malformed spec leaves the workspace untouched. If a
  per-tab mutation fails partway through (e.g. a tab disappeared
  between validation and execution), already-applied changes stay
  applied — there is no rollback.

* **Auto-close.** When a tab loses its last session as a side effect
  of a session moving away, the tab closes automatically. You don't
  need to list it in ``close_tabs``. Same idea for windows whose last
  tab goes away.

* **Cross-tab and cross-window moves work the same way** — both are
  expressed as a session GUID appearing in a different tab's ``root``
  than where it currently lives. ``apply_layout`` figures out the
  detach/reattach automatically.

* **Splitter rules.** Splitters need at least two children, and you
  can't nest a splitter of the same orientation as its parent (flatten
  it instead). ``apply_layout`` rejects either at validation time.

See :meth:`iterm2.App.async_apply_layout` for the full reference.

:Download:`Download<apply_layout.its>`
