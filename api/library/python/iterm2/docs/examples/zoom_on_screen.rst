Zoom on Screen
==============

The script clears "zooms" on the currently visible screen. It hides all text in the session other than what is currently visible, making it easy to perform searches without getting distracted by far-away results.

.. code-block:: python

    #!/usr/bin/env python3
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        window = app.current_terminal_window
        tab = window.current_tab
        session = tab.current_session

        # Select the screen contents. Note that selection "y" coordinates include
        # overflow, which is lines that have been lost because scrollback history
        # exceeded its limit. These coordinates are consistent across scroll events,
        # although they may refer to no-longer-visible lines.
        height, history, overflow, first = await session.async_get_number_of_lines()
        start = iterm2.Point(0, first + overflow)
        end = iterm2.Point(0, first + overflow + height)
        coordRange = iterm2.CoordRange(start, end)
        windowedCoordRange = iterm2.WindowedCoordRange(coordRange)
        sub = iterm2.SubSelection(windowedCoordRange, iterm2.SelectionMode.CHARACTER)
        selection = iterm2.Selection([sub])

        # Select the menu item that zooms on the selection.
        await session.async_set_selection(selection)
        await iterm2.MainMenu.async_select_menu_item(connection, "Zoom In on Selection")

    iterm2.run_until_complete(main)
