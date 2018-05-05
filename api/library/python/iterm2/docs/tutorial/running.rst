Running a Script
================

There are three ways to run a script:

1. From the Scripts menu.
2. At the command line.
3. Auto-run scripts launched when iTerm2 starts.

Scripts Menu
------------

The `Scripts` menu contains all the scripts in
`$HOME/Library/ApplicationSupport/iTerm2/Scripts`. The following files are
included:

  * Any file ending in `.py`. These correspond to "basic" scripts.
  * Any folder having an `itermenv` folder within it. These correspond to "full
    environment" scripts.
  * Applescript files, which are not the concern of this document.

To run a script from the menu, simply select it and it will run.

Command Line
------------

To invoke a script at the command line, you can simply run it as you would any
other command. Scripts are stored in
`$HOME/Library/ApplicationSupport/iTerm2/Scripts`.

Make sure you don't have a `PYTHONPATH` environment variable set when you run
your script.

.. note::

    iTerm2 creates the `ApplicationSupport` symlink to `Application
    Support` because shell scripts may not have spaces in their paths.

Auto-Run Scripts
----------------

If you'd like your script to launch automatically when iTerm2 starts, move it
to `$HOME/Library/ApplicationSupport/iTerm2/Scripts/AutoLaunch`.

Continue to the next section, :doc:`daemons`.


----

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
