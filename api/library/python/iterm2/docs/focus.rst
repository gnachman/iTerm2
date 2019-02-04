Focus
-----

.. autoclass:: iterm2.FocusMonitor
   :members: async_get_next_update

.. autoclass:: iterm2.FocusUpdate
   :members: application_active, window_changed, selected_tab_changed, active_session_changed

.. autoclass:: iterm2.FocusUpdateActiveSessionChanged
   :members: session_id

.. autoclass:: iterm2.FocusUpdateSelectedTabChanged
   :members: tab_id

.. autoclass:: iterm2.FocusUpdateWindowChanged
   :members: window_id, event, TERMINAL_WINDOW_BECAME_KEY, TERMINAL_WINDOW_IS_CURRENT, TERMINAL_WINDOW_RESIGNED_KEY

.. autoclass:: iterm2.FocusUpdateApplicationActive
   :members: application_active



----

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`

