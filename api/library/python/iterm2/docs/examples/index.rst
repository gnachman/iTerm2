.. _examples-index:
.. Example Scripts

Example Scripts
===============

Here are a collection of working scripts for you to crib from. While they are categorized according to their main function, some of them demonstrate more than one scripting feature. Search through this page or look for **See Also** sections in the documentation that link to examples demonstrating particular APIs.

-----------------------
Session Title Providers
-----------------------

:doc:`georges_title`
```````````````````````````````````

Demonstrates a session title provider.

:doc:`badgetitle`
```````````````````````````````````

Demonstrates a session title provider.

-----------------------
Status Bar Components
-----------------------

:doc:`statusbar`
```````````````````````````````````

Demonstrates a status bar component with variable-length text and a configurable knob.

:doc:`escindicator`
```````````````````````````````````

Demonstrates monitoring for keystrokes, custom status bar components, and using variables as a back-channel for communication between parts of a script.

:doc:`jsonpretty`
```````````````````````````````````

Demonstrates a status bar component that handles clicks and opens a popover with a web view.

:doc:`mousemode`
```````````````````````````````````

Demonstrates a status bar component that responds to changes in a variable.

-----------------------
Tmux
-----------------------

:doc:`tmux`
```````````````````

Demonstrates basic functions of the tmux integration API.

:doc:`tile`
```````````````````

Demonstrates sending a command to the tmux server in tmux integration mode.


-----------------------
Monitoring for Events
-----------------------

:doc:`random_color`
```````````````````

Demonstrates performing an action when a new session is created and using a color preset.

:doc:`colorhost`
```````````````````

Demonstrates monitoring for different kinds of events concurrently.

:doc:`theme`
```````````````````

Demonstrates monitoring a variable and using color presets.

:doc:`copycolor`
```````````````````

Demonstrates monitoring for session creation and using color presets.


--------------------------
Profiles and Color Presets
--------------------------

:doc:`current_preset`
``````````````````````

Demonstrates getting a session's profile and querying the list of color presets.

:doc:`blending`
```````````````````

Demonstrates registering a function and adjusting profiles' values.

:doc:`settabcolor`
```````````````````

Demonstrates changing a session's local profile without updating the underlying profile.

------------------
Standalone Scripts
------------------

:doc:`set_title_forever`
`````````````````````````

Demonstrates setting a session's name. Also demonstrates a script that's meant
to be run from the command line that will launch iTerm2 and wait until it's
able to connect before proceeding.

:doc:`launch_and_run`
`````````````````````

Demonstrates launching iTerm2 from the command line (if needed) and creating a
new window that runs a command.

-----------------------
Keyboard
-----------------------

:doc:`function_key_tabs`
`````````````````````````

Demonstrates changing the behavior of a keystroke.


-----------------------
Broadcasting Input
-----------------------

:doc:`enable_broadcasting`
````````````````````````````

Demonstrates broadcast domains.

:doc:`broadcast`
```````````````````

Demonstrates splitting panes, broadcast domains, filtering keystrokes, and sending input.


-----------------------
Windows and Tabs
-----------------------

:doc:`movetab`
```````````````````

Demonstrates moving tabs among windows.

:doc:`sorttabs`
```````````````````

Demonstrates reordering tabs in a window.

:doc:`mrutabs`
```````````````````

Demonstrates monitoring for changes in keyboard focus and reordering tabs in a window.


-----------------------
Asyncio
-----------------------

:doc:`close_to_the_right`
````````````````````````````

Demonstrates asyncio.gather to perform actions in parallel.

:doc:`darknight`
```````````````````

Demonstrates performing an action at a particular time of day.


-----------------------
Custom Toolbelt Tools
-----------------------
:doc:`targeted_input`
``````````````````````

Demonstrates custom toolbelt tool, broadcast domains, and sending input.


-----------------------
Selection
-----------------------

:doc:`zoom_on_screen`
``````````````````````

Demonstrates selecting a menu item and modifying the selection.


-----------------------
Other
-----------------------

:doc:`cls`
```````````````````

Demonstrates registering a function, injecting a control sequence, and iterating over sessions.

:doc:`create_window`
``````````````````````

Demonstrates custom control sequences.

:doc:`oneshot`
```````````````````

Demonstrates registering a function and showing a modal alert.


----

++++++++++++++
Other Sections
++++++++++++++

* :doc:`/index`

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
