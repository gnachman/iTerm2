"""Status bar customization interfaces."""

import base64
import json
import typing

import iterm2.api_pb2
import iterm2.capabilities
import iterm2.color
import iterm2.connection
import iterm2.registration
import iterm2.rpc
import iterm2.util


# pylint: disable=too-few-public-methods
# pylint: disable=too-many-arguments
# pylint: disable=too-many-instance-attributes
class Knob:
    """Represents a configuration setting on a status bar."""
    def __init__(self, knob_type, name, placeholder, json_default_value, key):
        self.__name = name
        self.__type = knob_type
        self.__placeholder = placeholder
        self.__json_default_value = json_default_value
        self.__key = key

    def to_proto(self):
        """Returns a protobuf representation."""
        proto = (iterm2.api_pb2.RPCRegistrationRequest.
                 StatusBarComponentAttributes.Knob())
        proto.name = self.__name
        proto.type = self.__type
        proto.placeholder = self.__placeholder
        proto.json_default_value = self.__json_default_value
        proto.key = self.__key
        return proto


class CheckboxKnob:
    """A status bar configuration knob to select a checkbox.

    :param name: Description of the knob.
    :param default_value: Default value (Boolean).
    :param key: A unique string key identifying this knob.
    """
    def __init__(self, name: str, default_value: bool, key: str):
        self.__knob = Knob(
            (iterm2.api_pb2.RPCRegistrationRequest.
             StatusBarComponentAttributes.Knob.Checkbox),
            name,
            "",
            json.dumps(default_value),
            key)

    def to_proto(self):
        """Returns a protobuf representation."""
        return self.__knob.to_proto()


class StringKnob:
    """A status bar configuration knob to select a string.

    :param name: Description of the knob.
    :param placeholder: Placeholder value (shown in gray) for the text field
        when it has no content.
    :param default_value: Default value.
    :param key: A unique string key identifying this knob.
    """
    def __init__(
            self, name: str, placeholder: str, default_value: str, key: str):
        self.__knob = Knob(
            (iterm2.api_pb2.RPCRegistrationRequest.
             StatusBarComponentAttributes.Knob.String),
            name,
            placeholder,
            json.dumps(default_value),
            key)

    def to_proto(self):
        """Returns a protobuf representation."""
        return self.__knob.to_proto()


class PositiveFloatingPointKnob:
    """
    A status bar configuration knob to select a positive floating point
    value.

    :param name: Description of the knob.
    :param default_value: Default value.
    :param key: A unique string key identifying this knob.
    """
    def __init__(self, name: str, default_value: float, key: str):
        self.__knob = Knob(
            (iterm2.api_pb2.RPCRegistrationRequest.
             StatusBarComponentAttributes.Knob.PositiveFloatingPoint),
            name,
            "",
            json.dumps(default_value),
            key)

    def to_proto(self):
        """Returns a protobuf representation."""
        return self.__knob.to_proto()


class ColorKnob:
    """A status bar configuration knob to select color.

    :param name: Description of the knob.
    :param default_value: Default value.
    :param key: A unique string key identifying this knob
    """
    def __init__(self, name: str, default_value: iterm2.color.Color, key: str):
        self.__knob = Knob(
            (iterm2.api_pb2.RPCRegistrationRequest.
             StatusBarComponentAttributes.Knob.Color),
            name,
            "",
            default_value.json, key)

    def to_proto(self):
        """Returns a protobuf representation."""
        return self.__knob.to_proto()


class StatusBarComponent:
    """Describes a script-provided status bar component showing a text value
    provided by a user-provided coroutine.

    :param short_description: Short description shown below the component in
        the picker UI.
    :param detailed_description: Tool tip for the component in the picker UI.
    :param knobs: List of configuration knobs. See the various Knob classes for
        details.
    :param exemplar: Example value to show in the picker UI as the sample
        content of the component.
    :param update_cadence: How frequently in seconds to reload the value, or
        `None` if it does not need to be reloaded on a timer.
    :param identifier: A string uniquely identifying this component. Use a
        backwards domain name. For example, `com.example.calculator` for a
        calculator component provided by example.com.
    :param icons: An array of `StatusBarComponent.Icon` objects. Should contain
        one with scale 1 and one with scale 2, of size 16x17 points. May be
        empty if you don't want an icon.

    .. seealso::
        * Example ":ref:`escindicator_example`"
        * Example ":ref:`jsonpretty_example`"
        * Example ":ref:`mousemode_example`"
        * Example ":ref:`statusbar_example`"
    """
    class Icon:
        """Contains a status bar icon.

        The scale gives the ratio between pixels and points. For example, a
        32x34 image with scale 2 has a size of 16x17 points.

        Status bar icons should be 16x17 points. Use a two point margin around
        the edges. The text baseline is 3.5 points up from the bottom of the
        image.

        :param scale: 2 for a retina (high-DPI) image, or 1 for a regular
            (low-DPI) image.
        :param base64_data: Base64-encoded data with the icon's image in PNG
            format.
        """
        def __init__(self, scale: float, base64_data: str):
            self.__scale = scale
            self.__data = base64.b64decode(base64_data)
            print(self.__data)

        def to_status_bar_icon(self):
            """Returns a protobuf representation."""
            proto = (iterm2.api_pb2.RPCRegistrationRequest.
                     StatusBarComponentAttributes.Icon())
            proto.data = self.__data
            proto.scale = self.__scale
            return proto

    # pylint: disable=dangerous-default-value
    def __init__(
            self,
            short_description: str,
            detailed_description: str,
            knobs: typing.List[Knob],
            exemplar: str,
            update_cadence: typing.Union[float, None],
            identifier: str,
            icons: typing.List[Icon] = []):
        """Initializes a status bar component."""
        self.__short_description = short_description
        self.__detailed_description = detailed_description
        self.__knobs = knobs
        self.__exemplar = exemplar
        self.__update_cadence = update_cadence
        self.__identifier = identifier
        self.__icons = icons
        self.__connection: typing.Optional[iterm2.connection.Connection] = None

    def set_fields_in_proto(self, proto):
        """Populates a protobuf from this object's contents."""
        proto.short_description = self.__short_description
        proto.detailed_description = self.__detailed_description
        knob_protos = list(map(lambda k: k.to_proto(), self.__knobs))
        proto.knobs.extend(knob_protos)
        proto.exemplar = self.__exemplar
        proto.unique_identifier = self.__identifier
        icons = list(map(lambda x: x.to_status_bar_icon(), self.__icons))
        proto.icons.extend(icons)
        if self.__update_cadence is not None:
            proto.update_cadence = self.__update_cadence

    async def async_open_popover(
            self, session_id: str, html: str, size: iterm2.util.Size):
        """Open a popover with a webview.

        :param session_id: The session identifier.
        :param html: A string containing HTML to show.
        :param size: The desired size of the popover, a
            :class:`~iterm2.util.Size`.

        .. seealso:: Example ":ref:`jsonpretty_example`"
        """
        await iterm2.rpc.async_open_status_bar_component_popover(
            self.__connection,
            self.__identifier,
            session_id,
            html,
            size)

    async def async_set_unread_count(
            self, session_id: typing.Optional[str], count: int):
        """
        Sets the unread count that is displayed in the status bar component. If
        0, it is removed.

        Requires iTerm2 version 3.3.2.

        :param session_id: The session identifier, or none to update all
            instances.
        :param count: The number to show, or 0 to remove it.
        :raises: AppVersionTooOld if not supported by this version of iTerm2.
        """
        if not iterm2.capabilities.supports_status_bar_unread_count(
                self.__connection):
            raise iterm2.capabilities.AppVersionTooOld(
                ("Unread count in status bar components is not " +
                 "supported in this version of iTerm2. Please upgrade " +
                 "to use this script."))

        invocation = iterm2.util.invocation_string(
            "iterm2.set_status_bar_component_unread_count",
            {"identifier": self.__identifier,
             "count": count})
        if session_id:
            await iterm2.rpc.async_invoke_method(
                self.__connection, session_id, invocation, -1)
        else:
            assert self.__connection
            await iterm2.async_invoke_function(self.__connection, invocation)

    async def async_register(
            self,
            connection: iterm2.connection.Connection,
            coro,
            timeout: typing.Union[None, float] = None,
            onclick: typing.Optional[
                typing.Callable[
                    [str, typing.Any],
                    typing.Coroutine[typing.Any, typing.Any, None]]] = None):
        """Registers the statusbar component.

        :param connection: A :class:`~iterm2.Connection`.
        :param coro: An async function. Its arguments are reflected upon to
            determine the RPC's signature. Only the names of the arguments are
            used. All arguments should be keyword arguments as any may be
            omitted at call time. It should take a special argument named
            "knobs" that is a dictionary with configuration settings. It may
            return a string or a list of strings. If it returns a list of
            strings then the longest one that fits will be used.
        :param timeout: How long iTerm2 should wait before giving up on this
            function's ever returning. `None` means to use the default timeout.
        :param onclick: A coroutine to run when the user clicks on the status
            bar component. It should take one argument, which is the session_id
            of the session owning the status bar component that was clicked on.

        Example:

          .. code-block:: python

              component = iterm2.StatusBarComponent(
                  short_description = "Session ID",
                  detailed_description = "Show the session's identifier",
                  knobs = [],
                  exemplar = "[session ID]",
                  update_cadence = None,
                  identifier = "com.iterm2.example.statusbar-rpc")

              @iterm2.StatusBarRPC
              async def session_id_status_bar_coro(
                      knobs,
                      session_id = iterm2.Reference("id")):
                  # This status bar component shows the current session ID,
                  # which is useful for debugging scripts.
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
                      onclick = my_status_bar_click_handler)
        """
        self.__connection = connection
        await coro.async_register(connection, self, timeout)
        if onclick:
            magic_name = "__" + self.__identifier.replace(
                ".", "_").replace("-", "_") + "__on_click"

            async def handle_rpc(session_id):
                await onclick(session_id)

            handle_rpc.__name__ = magic_name
            # This is an abuse of the RPC decorator, but it's a simple way to
            # register a function with a modified name.
            # pylint: disable=no-member
            await (iterm2.registration.RPC(handle_rpc).
                   async_register(connection, timeout=timeout))
