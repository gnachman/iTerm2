"""Defines interfaces for registering functions."""
import asyncio
import inspect
import iterm2.notifications
import iterm2.rpc
import json
import traceback
import websockets

async def generic_handle_rpc(coro, connection, notif):
    rpc_notif = notif.server_originated_rpc_notification
    params = {}
    ok = False
    try:
        for arg in rpc_notif.rpc.arguments:
            name = arg.name
            if arg.HasField("json_value"):
                # NOTE: This can throw an exception if there are control characters or other nasties.
                value = json.loads(arg.json_value)
                params[name] = value
            else:
                params[name] = None
        result = await coro(**params)
        ok = True
    except KeyboardInterrupt as e:
        raise e
    except websockets.exceptions.ConnectionClosed as e:
        raise e
    except Exception as e:
        tb = traceback.format_exc()
        exception = { "reason": repr(e), "traceback": tb }
        await iterm2.rpc.async_send_rpc_result(connection, rpc_notif.request_id, True, exception)

    if ok:
        await iterm2.rpc.async_send_rpc_result(connection, rpc_notif.request_id, False, result)

class Reference:
    """Defines a reference to a variable for use in the @RPC decorator.

    .. seealso::
        * :func:`~iterm2.registration.RPC`.
        * Example ":ref:`mousemode_example`"
        * Example ":ref:`statusbar_example`"
    """
    def __init__(self, name):
        self.name = name

def RPC(func):
    """A decorator that adds an `async_register` value to the coroutine it decorates. `async_register` is a coroutine that will register the function as an RPC.

    An RPC is a function in a script that iTerm2 can invoke in response to some action, such a a keypress or a trigger. You use this decorator to register a coroutine as an RPC.

    Every RPC must have a unique signature. The signature is composed of two parts: first, the name, which comes from the name of the coroutine being decorated; second, the names of its arguments. The order of arguments is not important.

    The decorated coroutine will have a `async_register` value that you must call to complete the registration. `async_register` takes one required argument, the :class:`~iterm2.connection.Connection`. It also takes one optional argument, which is a timeout. The `timeout` is a value in seconds. If not given, the default timeout will be used. When waiting for an RPC to return, iTerm2 will stop waiting for the RPC after the timeout elapses.

    Do not use default values for arguments in your decorated coroutine, with one exception: a special kind of default value of type :class:`iterm2.Reference`. It names a variable that is visible in the context of the invocation. It will be transformed to the current value of that variable. This is the only way to get information about the current context. For example, a value of `iterm2.Reference("id")` will give you the session ID of the context where the RPC was invoked. If the RPC is run from a keyboard shortcut, that is the ID of the session that had keyboard focus at the time of invocation.

    .. seealso::
        * Example ":ref:`badgetitle_example`"
        * Example ":ref:`blending_example`"
        * Example ":ref:`close_to_the_right_example`"
        * Example ":ref:`cls_example`"
        * Example ":ref:`jsonpretty_example`"
        * Example ":ref:`movetab_example`"

    That's complicated, but an example will make it clearer:

    Example:

      .. code-block:: python

          app = await iterm2.async_get_app(connection)

          @iterm2.RPC
          async def split_current_session_n_times(session_id=iterm2.Reference("id"), n=1):
              session = app.get_session_by_id(session_id)
              for i in range(n):
                  await session.async_split_pane()

          # Remember to call async_register!
          await split_current_session_n_times.async_register(connection)
    """
    async def async_register(connection, timeout=None):
        signature = inspect.signature(func)
        defaults = {}
        for k, v in signature.parameters.items():
            if isinstance(v.default, Reference):
                defaults[k] = v.default.name
        async def handle_rpc(connection, notif):
            await generic_handle_rpc(func, connection, notif)
        func.rpc_token = await iterm2.notifications.async_subscribe_to_server_originated_rpc_notification(
                connection,
                handle_rpc,
                func.__name__,
                signature.parameters.keys(),
                timeout,
                defaults,
                iterm2.notifications.RPC_ROLE_GENERIC)
        func.rpc_connection = connection

    func.async_register = async_register
    return func

def TitleProviderRPC(func):
    """A decorator that prepares a function for registration as a session title provider. Similar to :func:`~iterm2.registration.RPC`.

    A session title provider is a function that gets called to compute the title of a session. It may be called frequently, whenever the session title is deemed to need recomputation. Once registered, it appears as an option in the list of title settings in preferences.

    It is called when any of its inputs change. This will only happen if one or more of the inputs are :func:`~iterm2.registration.Reference` references to variables in the session context.

    It must return a string.

    Note that the `async_register` function is different than in the :func:`~iterm2.registration.RPC` decorator: it takes three arguments. The first is the :class:`~iterm2.connection.Connection`. The second is a "display name", which is the string to show in preferences that the user may select to use this title provider. The third is a string identifier, which must be unique among all title providers. The identifier should be a reverse DNS name, like `com.example.my-title-provider`. As long as the identifier remains the same from one version to the next, the display name and function signature may change.

    .. seealso:: Example ":ref:`georges_title_example`"

    Example:

      .. code-block:: python

          @iterm2.TitleProviderRPC
          async def upper_case_title(auto_name=iterm2.Reference("autoName?")):
              if not auto_name:
                  return ""
              return auto_name.upper()

          # Remember to call async_register!
          await upper_case_title.async_register(
                  connection,
                  display_name="Upper-case Title",
                  unique_identifier="com.iterm2.example.title-provider")
    """
    async def async_register(connection, display_name, unique_identifier, timeout=None):
        assert unique_identifier
        signature = inspect.signature(func)
        defaults = {}
        for k, v in signature.parameters.items():
            if isinstance(v.default, Reference):
                defaults[k] = v.default.name
        async def handle_rpc(connection, notif):
            await generic_handle_rpc(func, connection, notif)
        func.rpc_token = await iterm2.notifications.async_subscribe_to_server_originated_rpc_notification(
                connection=connection,
                callback=handle_rpc,
                name=func.__name__,
                arguments=signature.parameters.keys(),
                timeout_seconds=timeout,
                defaults=defaults,
                role=iterm2.notifications.RPC_ROLE_SESSION_TITLE,
                session_title_display_name=display_name,
                session_title_unique_id=unique_identifier)
        func.rpc_connection = connection

    func.async_register = async_register
    return func

def StatusBarRPC(func):
    """A decorator (like :func:`~iterm2.registration.RPC`) that registers a custom status bar component.

    See :class:`~iterm2.statusbar.StatusBarComponent` for details on what a status bar component is.

    The coroutine is called when any of its inputs change. This will only happen if one or more of the inputs are :func:`~iterm2.registration.Reference` references to variables in the session context.

    The coroutine *must* take an argument named `knobs` that will contain a dictionary with configuration settings.

    It may return a string or an array of strings. In the case that it returns an array, the longest string fitting the available space will be used.

    Note that unlike the other RPC decorators, you use :meth:`~iterm2.statusbar.StatusBarComponent.async_register` to register it, rather than a register property added to the coroutine.

    .. seealso::
        * Example ":ref:`escindicator_example`"
        * Example ":ref:`jsonpretty_example`"
        * Example ":ref:`mousemode_example`"
        * Example ":ref:`statusbar_example`"

    Example:

      .. code-block:: python

          component = iterm2.StatusBarComponent(
              short_description="Session ID",
              detailed_description="Show the session's identifier",
              knobs=[],
              exemplar="[session ID]",
              update_cadence=None,
              identifier="com.iterm2.example.statusbar-rpc")

          @iterm2.StatusBarRPC
          async def session_id_status_bar_coro(
                  knobs,
                  session_id=iterm2.Reference("id")):
              # This status bar component shows the current session ID, which
              # is useful for debugging scripts.
              return session_id

          @iterm2.RPC
          async def my_status_bar_click_handler(session_id):
              # When you click the status bar it opens a popover with the
              # message "Hello World"
              await component.async_open_popover(
                      session_id,
                      "Hello world",
                      iterm2.Size(200, 200))

          await component.async_register(
                  connection,
                  session_id_status_bar_coro,
                  onclick=my_status_bar_click_handler)
    """
    async def async_register(connection, component, timeout=None):
        signature = inspect.signature(func)
        defaults = {}
        for k, v in signature.parameters.items():
            if isinstance(v.default, Reference):
                defaults[k] = v.default.name

        async def wrapper(**kwargs):
            """handle_rpc->generic_handle_rpc->wrapper->func"""
            # Fix up knobs to not be JSON
            if "knobs" in kwargs:
                knobs_json = kwargs["knobs"]
                kwargs["knobs"] = json.loads(knobs_json)
            return await func(**kwargs)

        async def handle_rpc(connection, notif):
            """This gets run first."""
            await generic_handle_rpc(wrapper, connection, notif)

        func.rpc_token = await iterm2.notifications.async_subscribe_to_server_originated_rpc_notification(
                connection=connection,
                callback=handle_rpc,
                name=func.__name__,
                arguments=signature.parameters.keys(),
                timeout_seconds=timeout,
                defaults=defaults,
                role=iterm2.notifications.RPC_ROLE_STATUS_BAR_COMPONENT,
                status_bar_component=component)
        func.rpc_connection = connection

    func.async_register = async_register

    return func

