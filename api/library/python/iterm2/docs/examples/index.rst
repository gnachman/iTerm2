:orphan:

.. _examples-index:
.. Example Scripts

Example Scripts
===============

Here are a collection of working scripts for you to crib from. While they are categorized according to their main function, some of them demonstrate more than one scripting feature. Search through this page or look for **See Also** sections in the documentation that link to examples demonstrating particular APIs.

----

**Session Title Providers**

:doc:`georges_title` — Demonstrates a complex session title provider.

:doc:`badgetitle` — Demonstrates a simple session title provider.

----

**Status Bar Components**

:doc:`statusbar` — Demonstrates a status bar component with variable-length text and a configurable knob.

:doc:`escindicator` — Demonstrates monitoring for keystrokes, custom status bar components, and using variables as a back-channel for communication between parts of a script.

:doc:`jsonpretty` — Demonstrates a status bar component that handles clicks and opens a popover with a web view.

:doc:`mousemode` — Demonstrates a status bar component that responds to changes in a variable.

:doc:`gmtclock` - Demonstrates a status bar component that shows the current time in the GMT time zone.

:doc:`diskspace` - Demonstrates a status bar component that updates itself periodically, showing the amount of free disk space.

:doc:`unread` - Demonstrates a status bar component with an icon and an "unread count".

:doc:`weather` - Demonstrates fetching a web page periodically and showing its data in a custom status bar component. Also demonstrates providing an icon for a custom status bar component.

:doc:`venv` - A status bar component that shows the current Python virtual environment.

----

**Tmux**

:doc:`tmux` — Demonstrates basic functions of the tmux integration API.

:doc:`tile` — Demonstrates sending a command to the tmux server in tmux integration mode.


----

**Monitoring for Events**

:doc:`random_color` — Demonstrates performing an action when a new session is created and using a color preset.

:doc:`colorhost` — Demonstrates monitoring for different kinds of events concurrently.

:doc:`fs-only-status-bar` - Demonstrates monitoring for the creation of windows and the change of window style.

:doc:`theme` — Demonstrates monitoring a variable and using color presets.

:doc:`copycolor` — Demonstrates monitoring for session creation and using color presets.

:doc:`tabtitle` - Demonstrates monitoring for the creation of a new tab. Also demonstrates prompting the user for a string and changing a tab title.

:doc:`autoalert` - Demonstrates monitoring all sessions for long-running jobs. Also demonstrates posting notifications.

:doc:`stty` - Demonstrates watching for a variable to change in all sessions and sending text in response.

:doc:`app_tab_color` - Demonstrates watching for changes in the current foreground job. Updates the tab color as a function of the current command.

:doc:`sync_title` — Monitors for changes to a pane's title and copies it to the tab title. Demonstrates monitoring for changes to a variable and setting variables.

----

**Profiles and Color Presets**

:doc:`current_preset` — Demonstrates getting a session's profile and querying the list of color presets.

:doc:`blending` — Demonstrates registering a function and adjusting profiles' values.

:doc:`settabcolor` — Demonstrates changing a session's local profile without updating the underlying profile.

:doc:`increase_font_size` — Demonstrates changing a session's font without updating the underlying profile.

:doc:`resizeall` - Demonstrates registering a function that changes the font of all sessions in a window.

:doc:`change_default_profile` - Demonstrates changing the default profile.

:doc:`setprofile` - Demonstrates changing a session's profile.

----

**Standalone Scripts**

:doc:`set_title_forever` — Demonstrates setting a session's name. Also demonstrates a script that's meant to be run from the command line that will launch iTerm2 and wait until it's able to connect before proceeding.

:doc:`launch_and_run` — Demonstrates launching iTerm2 from the command line (if needed) and creating a new window that runs a command.

:doc:`runcommand` — Demonstrates running a command and capturing its output.

----

**Keyboard**

:doc:`function_key_tabs` — Demonstrates changing the behavior of a keystroke.


----

**Broadcasting Input**

:doc:`enable_broadcasting` — Demonstrates broadcast domains.

:doc:`broadcast` — Demonstrates splitting panes, broadcast domains, filtering keystrokes, and sending input.


----

**Windows and Tabs**

:doc:`movetab` — Demonstrates moving tabs among windows.

:doc:`sorttabs` — Demonstrates reordering tabs in a window.

:doc:`mrutabs` — Demonstrates monitoring for changes in keyboard focus and reordering tabs in a window. This script keeps tabs always in most-recently-used order, so the first tab is always selected.

:doc:`mrutabs2` - This script selects the next-most-recently-used tab when the current tab closes. Same for split panes.

:doc:`findps` - This script shows an alert prompting the user to enter a process ID and then reveals the pane that contains it.


----

**Asyncio**

:doc:`close_to_the_right` — Demonstrates asyncio.gather to perform actions in parallel.

:doc:`darknight` — Demonstrates performing an action at a particular time of day.


----

**Custom Toolbelt Tools**

:doc:`targeted_input` — Demonstrates custom toolbelt tool, broadcast domains, and sending input.


----

**Custom Context Menu Items**

:doc:`sumselection` - Demonstrates a custom context menu item that calculates the sum of selected numbers.


----

**Selection**

:doc:`zoom_on_screen` — Demonstrates selecting a menu item and modifying the selection.


----

**Other**

:doc:`cls` — Demonstrates registering a function, injecting a control sequence, and iterating over sessions.

:doc:`create_window` — Demonstrates custom control sequences.

:doc:`oneshot` — Demonstrates registering a function and showing a modal alert.

----

++++++++++++++
Other Sections
++++++++++++++

* :doc:`/index`

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
