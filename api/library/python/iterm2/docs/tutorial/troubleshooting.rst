Troubleshooting
===============

If anything goes wrong, remember to check the Script Console (**Scripts >
Manager > Console**). Pick your script on the left to view its output. Some
errors are also logged to the *iTerm2 App* history in the script console if
they cannot be tied to a running script.

If a script fails immediately saying something about a 401 error, that means
permission was denied. Check **Prefs > General > Magic > Permissions** and
verify that the script is not denied permission. The script console should also
provide more information about why it was denied.

Use print statements to write to the console. This is an essential technique
for debugging script issues.

If a session title provider is not registered, the title will show an ellipsis: `…`.

If a status bar provider is not registered or has some other problem (such as
an exception), it will show a ladybug: `🐞`. You can click on the ladybug to
get more details about the error.

Always catch exceptions in an async task. One of Python's rough edges is that
these exceptions are silently swallowed and you will pull your hair out trying
to understand what's wrong.

Take care to mark references optional by suffixing them with a `?` when they
might not exist, as is the case for `user.update_my_title_provider?` in the
last example in :doc:`hooks`.

If you get a runtime error, make sure you have the most recent version of the
Python runtime. Select **Scripts > Manage > Check for updated runtime** to
update it.

----

--------------
Other Sections
--------------

* :doc:`/index`
    * :doc:`index`
    * :doc:`example`
    * :doc:`running`
    * :doc:`daemons`
    * :doc:`rpcs`
    * :doc:`hooks`
    * Troubleshooting

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
