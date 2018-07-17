"""Status bar customization interfaces."""

import json
import iterm2.api_pb2

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
    """
    def __init__(self, name, short_description, detailed_description, knobs, exemplar, update_cadence):
        """Initializes a status bar component.
        """
        self.__name = name
        self.__short_description = short_description
        self.__detailed_description = detailed_description
        self.__knobs = knobs
        self.__exemplar = exemplar
        self.__update_cadence = update_cadence

    @property
    def name(self):
        return self.__name

    def set_fields_in_proto(self, proto):
        proto.short_description = self.__short_description
        proto.detailed_description = self.__detailed_description
        knob_protos = list(map(lambda k: k.to_proto(), self.__knobs))
        proto.knobs.extend(knob_protos)
        proto.exemplar = self.__exemplar
        if self.__update_cadence is not None:
            proto.update_cadence = self.__update_cadence

