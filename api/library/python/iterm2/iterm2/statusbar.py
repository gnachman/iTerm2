"""Status bar customization interfaces."""

import json
import iterm2.api_pb2
import iterm2.registration
import iterm2.rpc

class Knob:
    def __init__(self, type, name, placeholder, json_default_value, key):
        self.__name = name
        self.__type = type
        self.__placeholder = placeholder
        self.__json_default_value = json_default_value
        self.__key = key

    def to_proto(self):
        proto = iterm2.api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Knob()
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
    def __init__(self, name, default_value, key):
        self.__knob = Knob(iterm2.api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Knob.Checkbox, name, "", json.dumps(default_value), key)

    def to_proto(self):
        return self.__knob.to_proto()

class StringKnob:
    """A status bar configuration knob to select a string.

    :param name: Description of the knob.
    :param placeholder: Placeholder value (shown in gray) for the text field when it has no content.
    :param default_value: Default value.
    :param key: A unique string key identifying this knob.
    """
    def __init__(self, name, placeholder, default_value, key):
        self.__knob = Knob(iterm2.api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Knob.Checkbox, name, placeholder, json.dumps(default_value), key)

    def to_proto(self):
        return self.__knob.to_proto()

class PositiveFloatingPointKnob:
    """A status bar configuration knob to select a positive floating point value.

    :param name: Description of the knob.
    :param default_value: Default value.
    :param key: A unique string key identifying this knob.
    """
    def __init__(self, name, default_value, key):
        self.__knob = Knob(iterm2.api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Knob.Checkbox, name, "", json.dumps(default_value), key)

    def to_proto(self):
        return self.__knob.to_proto()

class ColorKnob:
    """A status bar configuration knob to select color.

    :param name: Description of the knob.
    :param default_value: Default value (a :class:`Color`)
    :param key: A unique string key identifying this knob
    """
    def __init__(self, name, default_value, key):
        self.__knob = Knob(iterm2.api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Knob.Checkbox, name, "", default_value.json, key)

    def to_proto(self):
        return self.__knob.to_proto()


class StatusBarComponent:
    """Describes a script-provided status bar component showing a text value provided by a user-provided coroutine.

    :param name: A unique name for this component.
    :param short_description: Short description shown below the component in the picker UI.
    :param detailed_description: Tool tip for th component in the picker UI.
    :param knobs: List of configuration knobs. See the various Knob classes for details.
    :param exemplar: Example value to show in the picker UI as the sample content of the component.
    :param update_cadence: How frequently in seconds to reload the value, or `None` if it does not need to be reloaded on a timer.
    :param identifier: A string uniquely identifying this component. Use a backwards domain name. For example, `com.example.calculator` for a calculator component provided by example.com.
    """
    def __init__(self, name, short_description, detailed_description, knobs, exemplar, update_cadence, identifier):
        """Initializes a status bar component.
        """
        self.__name = name
        self.__short_description = short_description
        self.__detailed_description = detailed_description
        self.__knobs = knobs
        self.__exemplar = exemplar
        self.__update_cadence = update_cadence
        self.__identifier = identifier
        self.__on_click = None

    @property
    def name(self):
        return self.__name

    def set_fields_in_proto(self, proto):
        proto.short_description = self.__short_description
        proto.detailed_description = self.__detailed_description
        knob_protos = list(map(lambda k: k.to_proto(), self.__knobs))
        proto.knobs.extend(knob_protos)
        proto.exemplar = self.__exemplar
        proto.unique_identifier = self.__identifier
        if self.__update_cadence is not None:
            proto.update_cadence = self.__update_cadence

    def set_click_handler(self, coro):
        """Sets a coroutine to call when the status bar component is clicked on.

        :param coro: A coroutine to run when the user clicks on the status bar component. It should take one argument, which is the session_id of the session owning the status bar component that was clicked on.
        """
        self.__on_click = coro

    async def async_open_popover(self, session_id, html, size):
        """Open a popover with a webview.

        :param session_id: The session identifier.
        :param html: A string containing HTML to show.
        :param size: The desired size of the popover, a :class:`iterm2.util.Size`.
        """
        await iterm2.rpc.async_open_status_bar_component_popover(
                self.__connection,
                self.__identifier,
                session_id,
                html,
                size)

    async def async_register(self, connection, coro, timeout=None, defaults={}):
        """Registers the statusbar component.

        :param connection: A :class:`iterm2.Connection`.
        :param coro: An async function. Its arguments are reflected upon to determine the RPC's signature. Only the names of the arguments are used. All arguments should be keyword arguments as any may be omitted at call time. It should take a special argument named "knobs" that is a dictionary with configuration settings. It may return a string or a list of strings. If it returns a list of strings then the longest one that fits will be used.
        :param timeout: How long iTerm2 should wait before giving up on this function's ever returning. `None` means to use the default timeout.
        :param defaults: Gives default values. Names correspond to argument names in `arguments`. Values are in-scope variables of the session owning the status bar.
        """
        self.__connection = connection
        await iterm2.registration.Registration.async_register_status_bar_component(
                connection,
                self,
                coro,
                timeout,
                defaults)
        if self.__on_click:
            await iterm2.registration.Registration.async_register_rpc_handler(
                    connection,
                    "__" + self.__identifier.replace(".", "_").replace("-", "_") + "__on_click",
                    self.__on_click)
