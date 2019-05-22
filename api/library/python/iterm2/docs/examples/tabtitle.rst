.. _tabtitle_example:

Tab Title
=========

This script prompts you to enter a tab title every time a new tab is created.

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        window = app.current_terminal_window

        def get_all_tab_ids():
           result = []
           for window in app.terminal_windows:
               for tab in window.tabs:
                   result.append(tab.tab_id)
           return set(result)

        async with iterm2.NewSessionMonitor(connection) as mon:
            before = get_all_tab_ids()
            while True:
                session_id = await mon.async_get()
                after = get_all_tab_ids()
                diff = after.difference(before)
                for tab_id in diff:
                    tab = app.get_tab_by_id(tab_id)
                    if tab is None:
                        continue
                    existing_title = (await tab.async_get_variable("titleOverride"))
                    if existing_title:
                        continue
                    await tab.async_select(True)
                    alert = iterm2.TextInputAlert("Edit Tab Title", "Enter the title for this tab.", "Tab title", "", app.get_window_for_tab(tab.tab_id).window_id)
                    try:
                        title = await alert.async_run(connection)
                        await tab.async_set_title(title)
                    except e:
                        print("WARNING - Could not edit tab title")
                        print(e)
                before = after

    iterm2.run_forever(main)


:Download:`Download<tabtitle.its>`

