.. _jsonpretty_example:

JSON Pretty Printer Status Bar Component
========================================

This script demonstrates a status bar component that can get the selected text, define an on-click handler, and open a popover showing HTML.

See :doc:`statusbar` for instructions on installing a custom status bar component.

.. code-block:: python

    import iterm2
    import json

    def tohtml(text):
        return "<pre>" + text.replace("&", "&amp;").replace("<", "&lt;") + "</pre>"

    def prettyprint(text):
        try:
            root = json.loads(text)
        except json.decoder.JSONDecodeError as e:
            return "Invalid JSON: {}".format(e)
        return json.dumps(root, sort_keys=True, indent=4)

    async def main(connection):
        app=await iterm2.async_get_app(connection)

        # Set the click handler
        @iterm2.RPC
        async def onclick(session_id):
            session = app.get_session_by_id(session_id)
            selection = await session.async_get_selection()
            selectedText = await session.async_get_selection_text(selection)
            await component.async_open_popover(session_id, tohtml(prettyprint(selectedText)), iterm2.util.Size(200, 200))

        # Define the configuration knobs:
        vl = "json_pretty_printer"
        knobs = [iterm2.CheckboxKnob("JSON Pretty Printer", False, vl)]
        component = iterm2.StatusBarComponent(
            short_description="JSON Pretty Printer",
            detailed_description="Select JSON in the terminal, then click this status bar component to see it nicely formatted.",
            knobs=knobs,
            exemplar="{ JSON }",
            update_cadence=None,
            identifier="com.iterm2.json-pretty-printer")

        # This function gets called whenever any of the paths named in defaults (below) changes
        # or its configuration changes.
        @iterm2.StatusBarRPC
        async def coro(knobs):
            return ["{ JSON }"]

        # Register the component.
        await component.async_register(connection, coro, onclick=onclick)

    iterm2.run_forever(main)

:Download:`Download<jsonpretty.its>`
