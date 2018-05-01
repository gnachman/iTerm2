#!/Users/gln/Library/ApplicationSupport/iTerm2/iterm2env/versions/3.6.5/bin/python3

import iterm2
import sys

async def main(connection, argv):
    a = await iterm2.app.get_app(connection)
    w = await a.create_window()
    t = w.tabs[0]
    s = t.get_sessions()[0]
    ns = await s.split_pane(vertical=True)
    await ns.split_pane(vertical=False)
    nt = await w.create_tab()
    await nt.get_sessions()[0].split_pane()

iterm2.connection.Connection().run(main, sys.argv)
