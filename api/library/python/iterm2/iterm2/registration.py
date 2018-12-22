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

class RPC:
    """Register a script-defined RPC.

    iTerm2 may be instructed to invoke a script-registered RPC, such as
    through a key binding. Use this class to register one.

    You must create a subclass that implements `async def coro(self, args)`,
    where `args` is zero or more arguments. Reflection is used to determine the
    unique signature of the RPC, which is a combination of the `name` passed to
    the `RPC` initializer plus the names of the arguments. All arguments should
    be keyword arguments, because they may be omitted depending on how the
    function is invoked.

    :param connection: The :class:`iterm2.Connection` to use.
    :param name: The RPC name. Combined with its arguments, this must be unique among all registered RPCs. It should consist of letters, numbers, and underscores and must begin with a letter.
    :param timeout: How long iTerm2 should wait before giving up on this function's ever returning. `None` means to use the default timeout.
    :param defaults: Gives default values. Names correspond to argument names in `coro`. Values are the names of variables that are in scope at the time the function is invoked. The variables' values will be passed as the values for those arguments.

    Example:

    This example registers an RPC that splits the specified session N times,
    where N is a value provided at runtime.

    There are many ways to invoke a function call. For example, you can
    register a key binding with the action "Invoke Script Function". You could
    give it a value like `split_pane(N=2)` to split the current pane twice when
    the key is pressed.

    The current session ID is passed as the `session_id` argument to coro because the variable named `session.id` is bound to it in the `defaults` argument.

      .. code-block: python

          app = await iterm2.async_get_app(conection)

          class SplitPaneRPC(iterm2.RPC):
              def __init__(self, connection):
                  super().__init__(connection, "split_pane", defaults={ "session_id": "session.id" })

              async def coro(self, session_id=None, N=1):
                  session = app.get_session_by_id(session_id)
                  if not session:
                      return
                  for i in range(N):
                      await session.async_split_pane()

          async with SplitPaneRPC(connection) as mon:
              await mon.async_wait_forever()
    """
    def __init__(connection, name, timeout=None, defaults={}):
        self.__connection = connection
        self.__name = name
        self.__timeout = timeout
        self.__defaults = defaults
        self.__queue = asyncio.Queue(loop=asyncio.get_event_loop())

    async def __aenter__(self):
        args = inspect.signature(self.coro).parameters.keys()[1:]

        async def handle_rpc(connection, notif):
            await generic_handle_rpc(coro, connection, notif)

        self.__token = await iterm2.notifications.async_subscribe_to_server_originated_rpc_notification(
                self.__connection,
                handle_rpc,
                self.__name,
                args,
                self.__timeout,
                self.__defaults,
                iterm2.notifications.RPC_ROLE_GENERIC)

    async def async_wait_forever(self):
        """A convenience function that never returns."""
        await asyncio.wait([asyncio.Future()])

    async def __aexit__(self, exc_type, exc, _tb):
        await iterm2.notifications.async_unsubscribe(self.__connection, self.__token)

class Reference:
    """Defines a reference to a variable for use in the @RPC decorator.

    See also: :func:`iterm2.registration.RPC`.
    """
    def __init__(self, name):
        self.name = name

def RPC(func):
    """A decorator that adds an `async_register` value to the coroutine it decorates. `async_register` is a coroutine that will register the function as an RPC.

    An RPC is a function in a script that iTerm2 can invoke in response to some action, such a a keypress or a trigger. You use this decorator to register a coroutine as an RPC.

    Every RPC must have a unique signature. The signature is composed of two parts: first, the name, which comes from the name of the coroutine being decorated; second, the names of its arguments. The order of arguments is not important.

    The decorated coroutine will have a `async_register` value that you must call to complete the registration. `async_register` takes one required argument, the :class:`iterm2.connection.Connection`. It also takes one optional argument, which is a timeout. The `timeout` is a value in seconds. If not given, the default timeout will be used. When waiting for an RPC to return, iTerm2 will stop waiting for the RPC after the timeout elapses.

    Do not use default values for arguments in your decorated coroutine, with one exception: a special kind of default value of type :class:`Reference`. It names a variable that is visible in the context of the invocation. It will be transformed to the current value of that variable. This is the only way to get information about the current context. For example, a value of `iterm2.Reference("session.id")` will give you the session ID of the context where the RPC was invoked. If the RPC is run from a keyboard shortcut, that is the ID of the session that had keyboard focus at the time of invocation.

    That's complicated, but an example will make it clearer:

    Example:

      .. code-block:: python

          app = await iterm2.async_get_app(connection)

          @iterm2.RPC
          async def split_current_session_n_times(session_id=iterm2.Reference("session.id"), n=1):
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

class Registration:
    @staticmethod
    async def async_register_session_title_provider(connection, name, coro, display_name, timeout=None, defaults={}):
        """Register a script-defined RPC.

        iTerm2 may be instructed to invoke a script-registered RPC, such as
        through a key binding. Use this method to register one.

        :param name: The RPC name. Combined with its arguments, this must be unique among all registered RPCs. It should consist of letters, numbers, and underscores and must begin with a letter.
        :param coro: An async function. Its arguments are reflected upon to determine the RPC's signature. Only the names of the arguments are used. All arguments should be keyword arguments as any may be omitted at call time.
        :param display_name: Gives the name of the function to show in preferences.
        :param timeout: How long iTerm2 should wait before giving up on this function's ever returning. `None` means to use the default timeout.
        :param defaults: Gives default values. Names correspond to argument names in `arguments`. Values are in-scope variables at the callsite.
        """
        async def handle_rpc(connection, notif):
            await generic_handle_rpc(coro, connection, notif)
        args = inspect.signature(coro).parameters.keys()
        await iterm2.notifications.async_subscribe_to_server_originated_rpc_notification(connection, handle_rpc, name, args, timeout, defaults, iterm2.notifications.RPC_ROLE_SESSION_TITLE, display_name)

    @staticmethod
    async def async_register_status_bar_component(connection, component, coro, timeout=None, defaults={}):
        """Registers a status bar component.

        :param component: A :class:`StatusBarComponent`.
        :param coro: An async function. Its arguments are reflected upon to determine the RPC's signature. Only the names of the arguments are used. All arguments should be keyword arguments as any may be omitted at call time. It should take a special argument named "knobs" that is a dictionary with configuration settings. It may return a string or a list of strings. If it returns a list of strings then the longest one that fits will be used.
        :param timeout: How long iTerm2 should wait before giving up on this function's ever returning. `None` means to use the default timeout.
        :param defaults: Gives default values. Names correspond to argument names in `arguments`. Values are in-scope variables of the session owning the status bar.
        """
        async def coro_wrapper(**kwargs):
            if "knobs" in kwargs:
                knobs_json = kwargs["knobs"]
                kwargs["knobs"] = json.loads(knobs_json)
            return await coro(**kwargs)

        async def handle_rpc(connection, notif):
            await generic_handle_rpc(coro_wrapper, connection, notif)

        args = inspect.signature(coro).parameters.keys()
        await iterm2.notifications.async_subscribe_to_server_originated_rpc_notification(
                connection,
                handle_rpc,
                component.name,
                args,
                timeout,
                defaults,
                iterm2.notifications.RPC_ROLE_STATUS_BAR_COMPONENT,
                None,
                component)

