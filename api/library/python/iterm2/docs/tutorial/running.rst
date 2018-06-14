Running a Script
================

There are four ways to run a script:

1. From the Scripts menu.
2. At the command line.
3. Auto-run scripts launched when iTerm2 starts.
4. With an interactive interpreter called a REPL.

Scripts Menu
------------

The `Scripts` menu contains all the scripts in
`$HOME/Library/ApplicationSupport/iTerm2/Scripts`. The following files are
included:

* Any file ending in `.py`. These correspond to "basic" scripts.
* Any folder having an `itermenv` folder within it. These correspond to "full environment" scripts.
* Applescript files, which are not the concern of this document.

To run a script from the menu, simply select it and it will run.

Command Line
------------

Your machine probably has `many instances of Python <https://xkcd.com/1987/>`_
installed in different places. It's important to run your script with the right
Python so that it can find the packages the script depends on (such as the
`iterm2` package).

The standard iTerm2 Python installation is at
`~/Library/ApplicationSupport/iTerm2/iterm2env/versions/3.6.5/bin/python3`.
This is the so-called "Basic" environment.

If you create a script with the "Full Environment" its instance of Python
will be in
`~/Library/ApplicationSupport/iTerm2/Scripts/YourScript/iterm2env/versions/3.6.5/bin/python3`.

Internally, iTerm2 runs a basic script by invoking:

.. code-block:: python

    ~/Library/ApplicationSupport/iTerm2/iterm2env/versions/3.6.5/bin/python3 YourScript.py


Scripts are stored in `$HOME/Library/ApplicationSupport/iTerm2/Scripts`.

Make sure you don't have a `PYTHONPATH` environment variable set when you run
your script.

.. note::

    iTerm2 creates the `ApplicationSupport` symlink to `Application
    Support` because shell scripts may not have spaces in their paths.

Auto-Run Scripts
----------------

If you'd like your script to launch automatically when iTerm2 starts, move it
to `$HOME/Library/ApplicationSupport/iTerm2/Scripts/AutoLaunch`.

REPL
----

iTerm2 also offers a *REPL*: a *Read-eval-print loop*. This is an interactive
Python interpreter where you can experiment with the scripting API. You can
enter commands and immediately see their results. It's available from the menu
item `Scripts > Open Python REPL`. It will open a window with an interactive
Python interpreter.

The REPL uses the `apython` script provided by aioconsole_ which extends Python
so that you can use `await` without having to put it inside an `async`
function. In other words, you don't need to write
`iterm2.Connection().run(main, sys.argv)` to launch a `main` function when in
the REPL. Instead, a typical REPL session would begin with:

.. code-block:: python

    import iterm2
    connection=await iterm2.Connection.async_create()
    app=await iterm2.async_get_app(connection)

When the REPL starts it prints a sample script so that you don't need to
remember this. You can just copy-paste it into the interpreter. Once you've got
an `app` the rest is easy :).

.. _aioconsole: https://github.com/vxgmichel/aioconsole

Continue to the next section, :doc:`daemons`.

----

--------------
Other Sections
--------------

* :doc:`/index`
    * :doc:`index`
    * :doc:`example`
    * Running a Script
    * :doc:`daemons`
    * :doc:`rpcs`
    * :doc:`hooks`

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
