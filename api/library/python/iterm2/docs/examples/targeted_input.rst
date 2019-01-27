.. _targeted_input_example:

Targeted Input
==============

iTerm2 has a "broadcast input" feature that lets you send keyboard input to
multiple sessions. The purpose of this script is to send a different string to
each session to which input is broadcast.

This script demonstrates a few things:

* Running a web server in the script process
* Registering a custom toolbelt tool
* Using broadcast domains
* Scripts with external dependencies

The web server provides the user interface that allows you to enter the text to
send to each session. The web page is rendered in a custom toolbelt tool the
user can choose to enable.

*Broadcast domains* are the abstraction that describes how keyboard input is
broadcast. Any keypress in a session belonging to a particular broadcast domain
goes to all sessions in that domain. A broadcast domain is a collection of
sessions, and all broadcast domains are disjoint.

This script depends on the aiohttp package. To install it, you must create this
script as a "full environment" script. When you select the **New Python Script**
menu item, choose **Full Environment** at the first prompt. After it is
created, run the following command (supposing you named it **TargetedInput**;
if it has a different name, modify the path below appropriately):

.. code-block:: bash

    ~/Library/ApplicationSupport/iTerm2/Scripts/TargetedInput/iterm2env/versions/*/bin/pip3 install aiohttp

Then, replace `targeted_input.py` with:

.. code-block:: python

    #!/usr/bin/env python3
    # NOTE: This script depends on aiohttp.
    import aiohttp
    import asyncio
    import iterm2
    from aiohttp import web

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        async def send_html(txt, request):
            binary = txt.encode('utf8')
            resp = web.StreamResponse()
            resp.content_length = len(binary)
            resp.content_type = 'text/html'
            await resp.prepare(request)
            await resp.write(binary)
            return resp

        def html_for_domain(domain):
            txt = '<hr/><form action="/send" method="POST">'
            n = 0
            for session in domain.sessions:
                txt += '{}: <input name="{}" type="text" value="Value to send to session {}" /><br/>'.format(n, session.session_id, n)
                n += 1
            txt += '<input type="Submit"></form>'
            return txt

        async def main_page(request):
            txt = '<a href="/">Refresh</a><br/>'
            if not app.broadcast_domains:
                txt += "Turn on broadcast input and click refresh"
            for domain in app.broadcast_domains:
                txt += html_for_domain(domain)
            return await send_html(txt, request)

        async def send(request):
            reader = await request.post()
            for session_id in reader.keys():
                value = reader[session_id]
                session = app.get_session_by_id(session_id)
                if session:
                    await session.async_send_text(value, suppress_broadcast=True)
            return await main_page(request)

        def init():
            webapp = web.Application()
            webapp.router.add_get('/', main_page)
            return webapp

        # Set up a web server on port 9999. The web pages give the script a user interface.
        webapp = web.Application()
        webapp.router.add_get('/', main_page)
        webapp.router.add_post('/send', send)
        runner = web.AppRunner(webapp)
        await runner.setup()
        site = web.TCPSite(runner, 'localhost', 9999)
        await site.start()

        # Register a custom toolbelt tool that shows the web pages served by the server in this script.
        await iterm2.tool.async_register_web_view_tool(connection, "Targeted Input", "com.iterm2.example.targeted-input", False, "http://localhost:9999/")

    iterm2.run_forever(main)

:Download:`Download<targeted_input.its>`

Run the script and then open the "Targeted Input" tool. It will appear in the
**Toolbelt** menu. Turn on broadcast input on a few sessions and hit the
*Refresh* link. Then you can enter a value for each session and press *Submit*
to see it in action.
