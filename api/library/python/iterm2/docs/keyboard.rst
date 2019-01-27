Keyboard
--------

Provides classes for monitoring keyboard activity and modifying how iTerm2 handles keystrokes.

.. autoclass:: iterm2.KeystrokeMonitor
  :members: async_get

.. autoclass:: iterm2.KeystrokeFilter

.. autoclass:: iterm2.Keystroke
  :members: characters, characters_ignoring_modifiers, modifiers, keycode

.. autoclass:: iterm2.KeystrokePattern
  :members: required_modifiers, forbidden_modifiers, keycodes, characters, characters_ignoring_modifiers

.. autoclass:: iterm2.Modifier
  :undoc-members:
  :members:

.. autoclass:: iterm2.Keycode
  :undoc-members:
  :members:

----

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
