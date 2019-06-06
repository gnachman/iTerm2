.. _mrutabs2_example:

Select MRU On Close
===================

When the current tab or session closes, this script selects the next most recently used tab or session.

.. code-block:: python

    #!/usr/bin/env python3.7
    #
    # This script selects the most recently used tab or split pane when the current
    # tab or split pane closes.

    import iterm2

    window_id_to_tab_ids = {}
    tab_id_to_session_ids = {}

    def init_window(window):
        """Initialize the window -> tab list for one window"""
        global window_id_to_tab_ids
        window_id_to_tab_ids[window.window_id] = list(map(lambda x: x.tab_id, window.tabs))

        for tab in window.tabs:
            init_tab(tab)

    def init_tab(tab):
        """Initialize the tab -> session list for one tab"""
        global tab_id_to_session_ids
        tab_id_to_session_ids[tab.tab_id] = list(map(lambda x: x.session_id, tab.sessions))

    def init_window_if_needed(w):
        """Record the tab order in window w if it doesn't already exist."""
        global window_id_to_tab_ids
        if w.window_id in window_id_to_tab_ids:
            return
        init_window(w)

    def init_tab_if_needed(t):
        """Record the tab order in tab t if it doesn't already exist."""
        global tab_id_to_session_ids
        if t.tab_id in tab_id_to_session_ids:
            return
        init_tab(t)

    def refresh_window(window):
        """Remove defunct tabs and add new tabs to tab list for window"""
        global window_id_to_tab_ids
        tab_ids = list(map(lambda x: x.tab_id, window.tabs))

        # Remove defunct tabs
        if window.window_id in window_id_to_tab_ids:
            existing = window_id_to_tab_ids[window.window_id] 
        else:
            existing  = []
        updated = list(filter(lambda x: x in tab_ids, existing))

        # Add any newly discovered tabs to the end
        for t in window.tabs:
            if t.tab_id not in updated:
                updated.append(t.tab_id)

        window_id_to_tab_ids[window.window_id] = updated

    def refresh_tab(tab):
        """Remove defunct sessions and add new sessions to session list for tab"""
        global tab_id_to_session_ids
        session_ids = list(map(lambda x: x.session_id, tab.sessions))

        # Remove defunct sessions
        if tab.tab_id in tab_id_to_session_ids:
            existing = tab_id_to_session_ids[tab.tab_id]
        else:
            existing = []
        updated = list(filter(lambda x: x in session_ids, existing))

        # Add any newly discovered sessions to the end
        for s in tab.sessions:
            if s.session_id not in updated:
                updated.append(s.session_id)

        tab_id_to_session_ids[tab.tab_id] = updated

    def get_mru_tab_id(window):
        """Returns the most recently used tab ID in this window"""
        global window_id_to_tab_ids
        if window.window_id not in window_id_to_tab_ids:
            return None
        tab_ids = window_id_to_tab_ids[window.window_id]
        if len(tab_ids) == 0:
            return None
        return tab_ids[0]

    def get_mru_session_id(tab):
        """Returns the most recently used session ID in this tab"""
        global tab_id_to_session_ids
        if tab.tab_id not in tab_id_to_session_ids:
            return None
        session_ids = tab_id_to_session_ids[tab.tab_id]
        if len(session_ids) == 0:
            return None
        return session_ids[0]

    def get_successor_tab_id(window, tab_id):
        """When a tab is closed, select the next most recently used tab. Remove any defunct tabs from the MRU list."""
        refresh_window(window)
        mru_tab_id = get_mru_tab_id(window)
        if not mru_tab_id:
            return None
        if mru_tab_id == tab_id:
            return None
        return mru_tab_id

    def get_successor_session_id(session, tab):
        """When a session is closed, select the next most recently used session. Remove any defunct sessions from the MRU list."""
        refresh_tab(tab)
        mru_session_id = get_mru_session_id(tab)
        if not mru_session_id:
            return None
        if mru_session_id == session.session_id:
            return None
        return mru_session_id

    def update_mru_tab(window_id, tab_id):
        """When a tab gets selected, move it to the head of the MRU list"""
        global window_id_to_tab_ids
        if window_id in window_id_to_tab_ids:
            ids = window_id_to_tab_ids[window_id]
        else:
            ids = []
        if tab_id in ids:
            i = ids.index(tab_id)
            del ids[i]
        ids.insert(0, tab_id)
        window_id_to_tab_ids[window_id] = ids

    def update_mru_session(tab_id, session_id):
        """When a session gets selected, move it to the head of the MRU list"""
        global tab_id_to_session_ids
        if tab_id in tab_id_to_session_ids:
            ids = tab_id_to_session_ids[tab_id]
        else:
            ids = []
        if session_id in ids:
            i = ids.index(session_id)
            del ids[i]
        ids.insert(0, session_id)
        tab_id_to_session_ids[tab_id] = ids

    def tab_known(tab_id, window):
        """Do we already know about this tab and window combination?"""
        global window_id_to_tab_ids
        if window.window_id not in window_id_to_tab_ids:
            return False
        return tab_id in window_id_to_tab_ids[window.window_id]

    def session_known(session_id, tab):
        """Do we already know about this session and tab combination?"""
        global tab_id_to_session_ids
        if tab.tab_id not in tab_id_to_session_ids:
            return False
        return session_id in tab_id_to_session_ids[tab.tab_id]

    def window_has_closed_tabs(window):
        """Are there tab IDs in the MRU list not in the actual set of tabs?"""
        global window_id_to_tab_ids
        actual_tab_ids = list(map(lambda x: x.tab_id, window.tabs))
        for mru_tab_id in window_id_to_tab_ids[window.window_id]:
            if mru_tab_id not in actual_tab_ids:
                return True
        return False

    def tab_has_closed_sessions(tab):
        """Are there session IDs in the MRU list not in the actual set of sessions?"""
        global tab_id_to_session_ids
        actual_session_ids = list(map(lambda x: x.session_id, tab.sessions))
        for mru_session_id in tab_id_to_session_ids[tab.tab_id]:
            if mru_session_id not in actual_session_ids:
                return True
        return False

    def add_tab_to_window(window_id, tab_id):
        """Add a tab ID to the MRU list for a window."""
        global window_id_to_tab_ids
        if window_id in window_id_to_tab_ids:
            ids = window_id_to_tab_ids[window_id]
        else:
            ids = []
        ids.insert(0, tab_id)
        window_id_to_tab_ids[window_id] = ids

    def add_session_to_tab(tab_id, session_id):
        """Add a session ID to the MRU list for a tab."""
        global tab_id_to_session_ids
        if tab_id in tab_id_to_session_ids:
            ids = tab_id_to_session_ids[tab_id]
        else:
            ids = []
        ids.insert(0, session_id)
        tab_id_to_session_ids[tab_id] = ids

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        for window in app.terminal_windows:
            init_window(window)

        async def handle_close_tab(window, tab_id):
            """A tab was closed"""
            mru_tab_id = get_successor_tab_id(window, tab_id)
            if not mru_tab_id:
                return
            tab = app.get_tab_by_id(mru_tab_id)
            if tab:
                await tab.async_select()

        async def handle_close_session(session, tab):
            """A session was closed"""
            mru_session_id = get_successor_session_id(session, tab)
            if not mru_session_id:
                return
            session = app.get_session_by_id(mru_session_id)
            if session:
                await session.async_activate()

        async def handle_selected_tab_changed(tab_id):
            """The selected tab changed"""
            tab = app.get_tab_by_id(update.selected_tab_changed.tab_id)
            if not tab:
                return

            window = app.get_window_for_tab(tab_id)
            if not window:
                return

            init_tab_if_needed(tab)
            init_window_if_needed(window)
            if not tab_known(tab_id, window):
                add_tab_to_window(window.window_id, tab_id)
                return

            if window_has_closed_tabs(window):
                await handle_close_tab(window, tab_id)
            else:
                update_mru_tab(window.window_id, tab_id)

        def handle_window_became_key(window_id):
            """A window got keyboard focus"""
            w = app.get_window_by_id(window_id)
            if w:
                init_window_if_needed(w)

        async def handle_session_selected(session_id):
            """The selected session changed"""
            s = app.get_session_by_id(session_id)
            if not s:
                return
            window, tab = app.get_tab_and_window_for_session(s)
            if not tab:
                return

            init_tab_if_needed(tab)
            init_window_if_needed(window)
            if not session_known(session_id, tab):
                add_session_to_tab(tab.tab_id, s.session_id)
                return

            if tab_has_closed_sessions(tab):
                await handle_close_session(s, tab)
            else:
                update_mru_session(tab.tab_id, s.session_id)

        # Watch for changes to keyboard focus and update state and active tab/session as needed.
        async with iterm2.FocusMonitor(connection) as monitor:
            while True:
                update = await monitor.async_get_next_update()
                if update.selected_tab_changed:
                    await handle_selected_tab_changed(update.selected_tab_changed.tab_id)
                    continue
                if update.active_session_changed:
                    await handle_session_selected(update.active_session_changed.session_id)
                    continue
                if (update.window_changed and 
                        update.window_changed.event == iterm2.FocusUpdateWindowChanged.Reason.TERMINAL_WINDOW_BECAME_KEY):
                    handle_window_became_key(update.window_changed.window_id)
                    continue

    iterm2.run_forever(main)

:Download:`Download<mrutabs2.its>`
