"""Defines interfaces for registering functions."""
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

class Registration:
    @staticmethod
    async def async_register_rpc_handler(connection, name, coro, timeout=None, defaults={}):
        """Register a script-defined RPC.

        iTerm2 may be instructed to invoke a script-registered RPC, such as
        through a key binding. Use this method to register one.

        :param name: The RPC name. Combined with its arguments, this must be unique among all registered RPCs. It should consist of letters, numbers, and underscores and must begin with a letter.
        :param coro: An async function. Its arguments are reflected upon to determine the RPC's signature. Only the names of the arguments are used. All arguments should be keyword arguments as any may be omitted at call time.
        :param timeout: How long iTerm2 should wait before giving up on this function's ever returning. `None` means to use the default timeout.
        :param defaults: Gives default values. Names correspond to argument names in `arguments`. Values are in-scope variables at the callsite.
        """
        args = inspect.signature(coro).parameters.keys()
        async def handle_rpc(connection, notif):
            await generic_handle_rpc(coro, connection, notif)
        await iterm2.notifications.async_subscribe_to_server_originated_rpc_notification(connection, handle_rpc, name, args, timeout, defaults, iterm2.notifications.RPC_ROLE_GENERIC)

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

