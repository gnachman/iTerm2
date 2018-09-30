Function Key Tabs
=================

The script makes it possible to select a tab by pressing a function key. F1 chooses the first tab, F2 the second, etc.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
	app = await iterm2.async_get_app(connection)
        # Keycodes for f1 through f10. See here for a list:
        # https://stackoverflow.com/questions/3202629/where-can-i-find-a-list-of-mac-virtual-key-codes
	keycodes = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109 ]
	async def keystroke_handler(connection, notification):
	    if notification.modifiers == [ iterm2.api_pb2.Modifiers.Value("FUNCTION") ]:
                try:
		  fkey = keycodes.index(notification.keyCode)
		  if fkey >= 0 and fkey < len(app.current_terminal_window.tabs):
		      await app.current_terminal_window.tabs[fkey].async_select()
                except:
                  pass

	patterns = iterm2.KeystrokePattern()
	patterns.forbidden_modifiers.extend([iterm2.MODIFIER_CONTROL,
                                             iterm2.MODIFIER_OPTION,
                                             iterm2.MODIFIER_COMMAND,
                                             iterm2.MODIFIER_SHIFT,
                                             iterm2.MODIFIER_NUMPAD])
	patterns.required_modifiers.extend([iterm2.MODIFIER_FUNCTION])
	patterns.keycodes.extend(keycodes)

	await iterm2.notifications.async_subscribe_to_keystroke_notification(connection, keystroke_handler, patterns_to_ignore=[patterns])

    iterm2.run_forever(main)

