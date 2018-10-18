Enable Broadcasting Input
=========================
 It turns on input broadcasting for the first session in each tab of the first window.
This example demonstrates how to manipulate which sessions broadcast input.

Input broadcasting happens among the sessions belonging to a particular window.

There may be multiple "broadcast domains". Each broadcast domain has a collection of sessions belonging to a window. There may not be more than one broadcast domain per window.







for tab in app.terminal_windows[0].tabs:
tab
tab
tab  d = domaidomaidomaidomainterm2.broadcast.BroadcastDomain()
d.add_session(app.terminal_windows[0].tabs[2].sessions[0]domain
await app.async_set_broadcast_domains([d])

iterm2.run_until_complete(main)

