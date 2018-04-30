import json
import iterm2.rpc

class WriteOnlyProfile:
  """A profile that can be modified but not read. Useful for changing many
  sessions' profiles at once without knowing what they are."""
  def __init__(self, session_id, connection):
    self.connection = connection
    self.session_id = session_id

  async def _simple_set(self, key, value):
    """value is a json type"""
    await iterm2.rpc.set_profile_property(self.connection, self.session_id, key, value)

  async def _color_set(self, key, value):
    if value is None:
      await iterm2.rpc.set_profile_property(self.connection, self.session_id, key, "null")
    else:
      await iterm2.rpc.set_profile_property(self.connection, self.session_id, key, value.get_dict())

  async def set_foreground_color(self, value):
    """Sets the foreground color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Foreground Color", value)

  async def set_background_color(self, value):
    """Sets the background color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Background Color", value)

  async def set_bold_color(self, value):
    """Sets the bold text color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Bold Color", value)

  async def set_link_color(self, value):
    """Sets the link color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Link Color", value)

  async def set_selection_color(self, value):
    """Sets the selection background color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Selection Color", value)

  async def set_selected_text_color(self, value):
    """Sets the selection text color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Selected Text Color", value)

  async def set_cursor_color(self, value):
    """Sets the cursor color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Cursor Color", value)

  async def set_cursor_text_color(self, value):
    """Sets the cursor text color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Cursor Text Color", value)

  async def set_ansi_0_color(self, value):
    """Sets the ANSI 0 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 0 Color", value)

  async def set_ansi_1_color(self, value):
    """Sets the ANSI 1 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 1 Color", value)

  async def set_ansi_2_color(self, value):
    """Sets the ANSI 2 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 2 Color", value)

  async def set_ansi_3_color(self, value):
    """Sets the ANSI 3 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 3 Color", value)

  async def set_ansi_4_color(self, value):
    """Sets the ANSI 4 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 4 Color", value)

  async def set_ansi_5_color(self, value):
    """Sets the ANSI 5 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 5 Color", value)

  async def set_ansi_6_color(self, value):
    """Sets the ANSI 6 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 6 Color", value)

  async def set_ansi_7_color(self, value):
    """Sets the ANSI 7 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 7 Color", value)

  async def set_ansi_8_color(self, value):
    """Sets the ANSI 8 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 8 Color", value)

  async def set_ansi_9_color(self, value):
    """Sets the ANSI 9 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 9 Color", value)

  async def set_ansi_10_color(self, value):
    """Sets the ANSI 10 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 10 Color", value)

  async def set_ansi_11_color(self, value):
    """Sets the ANSI 11 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 11 Color", value)

  async def set_ansi_12_color(self, value):
    """Sets the ANSI 12 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 12 Color", value)

  async def set_ansi_13_color(self, value):
    """Sets the ANSI 13 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 13 Color", value)

  async def set_ansi_14_color(self, value):
    """Sets the ANSI 14 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 14 Color", value)

  async def set_ansi_15_color(self, value):
    """Sets the ANSI 15 color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Ansi 15 Color", value)

  async def set_smart_cursor_color(self, value):
    """Sets the smart cursor color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Smart Cursor Color", value)

  async def set_tab_color(self, value):
    """Sets the tab color.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Tab Color", value)

  async def set_underline_color(self, value):
    """Sets the underline color.

    :param value: An iterm2.profile.Color or None"""
    return await self._color_set("Underline Color", value)

  async def set_cursor_guide_color(self, value):
    """Sets the cursor guide color. The alpha value is respected.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Cursor Guide Color", value)

  async def set_badge_color(self, value):
    """Sets the badge color. The alpha value is respected.

    :param value: An iterm2.profile.Color"""
    return await self._color_set("Badge Color", value)

  async def set_name(self, value):
    """Sets the name.

    :param value: A string"""
    return await self._simple_set("Name", value)

  async def set_badge_text(self, value):
    """Sets the badge text.

    :param value: An iterm2.profile.Color"""
    return await self._simple_set("Badge Text", value)

  async def set_answerback_string(self, value):
    """Sets the answerback string.

    :param value: A string"""
    return await self._simple_set("Answerback String", value)

  async def set_use_cursor_guide(self, value):
    """Sets whether the cursor guide should be used.

    :param value: A boolean"""
    return await self._simple_set("Use Cursor Guide", value)

  async def set_use_tab_color(self, value):
    """Sets whether the tab color should be used.

    :param value: A string"""
    return await self._simple_set("Use Tab Color", value)

  async def set_use_underline_color(self, value):
    """Sets the underline color.

    :param value: An iterm2.profile.Color"""
    return await self._simple_set("Use Underline Color", value)

  async def set_smart_cursor_color(self, value):
    """Sets the smart cursor text color.

    :param value: A string"""
    return await self._simple_set("Smart Cursor Color", value)

  async def set_minimum_contrast(self, value):
    """Sets the minimum contrast.

    :param value: A float in 0 to 1"""
    return await self._simple_set("Minimum Contrast", value)

  async def set_cursor_boost(self, value):
    """Sets the cursor boost level.

    :param value: A float in 0 to 1"""
    return await self._simple_set("Cursor Boost", value)

  async def set_blinking_cursor(self, value):
    """Sets whether the cursor blinks.

    :param value: A bool"""
    return await self._simple_set("Blinking Cursor", value)

  async def set_use_bold_font(self, value):
    """Sets whether to use the bold variant of the font for bold text.

    :param value: A bool"""
    return await self._simple_set("Use Bold Font", value)

  async def set_ascii_ligatures(self, value):
    """Sets whether ligatures should be used for ASCII text.

    :param value: A bool"""
    return await self._simple_set("ASCII Ligatures", value)

  async def set_non_ascii_ligatures(self, value):
    """Sets whether ligatures should be used for non-ASCII text.

    :param value: A bool"""
    return await self._simple_set("Non-ASCII Ligatures", value)

  async def set_use_bright_bold(self, value):
    """Sets whether bright colors should be used for bold text.

    :param value: A bool"""
    return await self._simple_set("Use Bright Bold", value)

  async def set_blink_allowed(self, value):
    """Sets whether blinking text is allowed.

    :param value: A bool"""
    return await self._simple_set("Blink Allowed", value)

  async def set_use_italic_font(self, value):
    """Sets whether italic text is allowed.

    :param value: A bool"""
    return await self._simple_set("Use Italic Font", value)

  async def set_ambiguous_double_width(self, value):
    """Sets whether ambiguous-width text should be treated as double-width.

    :param value: A bool"""
    return await self._simple_set("Ambiguous Double Width", value)

  async def set_horizontal_spacing(self, value):
    """Sets the fraction of horizontal spacing.

    :param value: A float at least 0"""
    return await self._simple_set("Horizontal Spacing", value)

  async def set_vertical_spacing(self, value):
    """Sets the fraction of vertical spacing.

    :param value: A float at least 0"""
    return await self._simple_set("Vertical Spacing", value)

  async def set_use_non_ascii_font(self, value):
    """Sets whether to use a different font for non-ASCII text.

    :param value: A bool"""
    return await self._simple_set("Use Non-ASCII Font", value)

  async def set_transparency(self, value):
    """Sets the level of transparency.

    :param value: A float between 0 and 1"""
    return await self._simple_set("Transparency", value)

  async def set_blur(self, value):
    """Sets whether background blur should be enabled.

    :param value: A bool"""
    return await self._simple_set("Blur", value)

  async def set_blur_radius(self, value):
    """Sets the blur radius (how blurry). Requires blur to be enabled.

    :param value: A float between 0 and 30"""
    return await self._simple_set("Blur Radius", value)

  async def set_background_image_is_tiled(self, value):
    """Sets whether the background image is tiled (true) or stretched (false)

    :param value: A bool"""
    return await self._simple_set("Background Image Is Tiled", value)

  async def set_blend(self, value):
    """Sets how much the default background color gets blended with the background image.

    :param value: A float in 0 to 1"""
    return await self._simple_set("Blend", value)

  async def set_sync_title(self, value):
    """Sets whether the profile name stays in the tab title, even if changed by an escape sequence.

    :param value: A bool"""
    return await self._simple_set("Sync Title", value)

  async def set_disable_window_resizing(self, value):
    """Sets whether the terminal can resize the window with an escape sequence.

    :param value: A bool"""
    return await self._simple_set("Disable Window Resizing", value)

  async def set_only_the_default_bg_color_uses_transparency(self, value):
    """Sets whether window transparency shows through non-default background colors.

    :param value: A bool"""
    return await self._simple_set("Only The Default BG Color Uses Transparency", value)

  async def set_ascii_anti_aliased(self, value):
    """Sets whether ASCII text is anti-aliased.

    :param value: A bool"""
    return await self._simple_set("ASCII Anti Aliased", value)

  async def set_non_ascii_anti_aliased(self, value):
    """Sets whether non-ASCII text is anti-aliased.

    :param value: A bool"""
    return await self._simple_set("Non-ASCII Anti Aliased", value)

  async def set_scrollback_lines(self, value):
    """Sets the number of scrollback lines.

    :param value: An int at least 0"""
    return await self._simple_set("Scrollback Lines", value)

  async def set_unlimited_scrollback(self, value):
    """Sets whether the scrollback buffer's length is unlimited.

    :param value: A bool"""
    return await self._simple_set("Unlimited Scrollback", value)

  async def set_scrollback_with_status_bar(self, value):
    """Sets whether text gets appended to scrollback when there is an app status bar

    :param value: A bool"""
    return await self._simple_set("Scrollback With Status Bar", value)

  async def set_scrollback_in_alternate_screen(self, value):
    """Sets whether text gets appended to scrollback in alternate screen mode

    :param value: A bool"""
    return await self._simple_set("Scrollback in Alternate Screen", value)

  async def set_mouse_reporting(self, value):
    """Sets whether mouse reporting is allowed

    :param value: A bool"""
    return await self._simple_set("Mouse Reporting", value)

  async def set_mouse_reporting_allow_mouse_wheel(self, value):
    """Sets whether mouse reporting reports the mouse wheel's movements.

    :param value: A bool"""
    return await self._simple_set("Mouse Reporting allow mouse wheel", value)

  async def set_allow_title_reporting(self, value):
    """Sets whether the session title can be reported

    :param value: A bool"""
    return await self._simple_set("Allow Title Reporting", value)

  async def set_allow_title_setting(self, value):
    """Sets whether the session title can be changed by escape sequence

    :param value: A bool"""
    return await self._simple_set("Allow Title Setting", value)

  async def set_disable_printing(self, value):
    """Sets whether printing by escape sequence is disabled.

    :param value: A bool"""
    return await self._simple_set("Disable Printing", value)

  async def set_disable_smcup_rmcup(self, value):
    """Sets whether alternate screen mode is disabled

    :param value: A bool"""
    return await self._simple_set("Disable Smcup Rmcup", value)

  async def set_silence_bell(self, value):
    """Sets whether the bell makes noise.

    :param value: A bool"""
    return await self._simple_set("Silence Bell", value)

  async def set_bm_growl(self, value):
    """Sets whether notifications should be shown.

    :param value: A bool"""
    return await self._simple_set("BM Growl", value)

  async def set_send_bell_alert(self, value):
    """Sets whether notifications should be shown for the bell ringing

    :param value: A bool"""
    return await self._simple_set("Send Bell Alert", value)

  async def set_send_idle_alert(self, value):
    """Sets whether notifications should be shown for becoming idle

    :param value: A bool"""
    return await self._simple_set("Send Idle Alert", value)

  async def set_send_new_output_alert(self, value):
    """Sets whether notifications should be shown for new output

    :param value: A bool"""
    return await self._simple_set("Send New Output Alert", value)

  async def set_send_session_ended_alert(self, value):
    """Sets whether notifications should be shown for a session ending

    :param value: A bool"""
    return await self._simple_set("Send Session Ended Alert", value)

  async def set_send_terminal_generated_alerts(self, value):
    """Sets whether notifications should be shown for escape-sequence originated notifications

    :param value: A bool"""
    return await self._simple_set("Send Terminal Generated Alerts", value)

  async def set_flashing_bell(self, value):
    """Sets whether the bell should flash the screen

    :param value: A bool"""
    return await self._simple_set("Flashing Bell", value)

  async def set_visual_bell(self, value):
    """Sets whether a bell should be shown when the bell rings

    :param value: A bool"""
    return await self._simple_set("Visual Bell", value)

  async def set_close_sessions_on_end(self, value):
    """Sets whether the session should close when it ends.

    :param value: A bool"""
    return await self._simple_set("Close Sessions On End", value)

  async def set_prompt_before_closing(self, value):
    """Sets whether the session should prompt before closign

    :param value: A bool"""
    return await self._simple_set("Prompt Before Closing 2", value)

  async def set_session_close_undo_timeout(self, value):
    """Sets amount of time you can undo closing a session

    :param value: A float at least 0"""
    return await self._simple_set("Session Close Undo Timeout", value)

  async def set_reduce_flicker(self, value):
    """Sets whether the flicker fixer is on.

    :param value: A bool"""
    return await self._simple_set("Reduce Flicker", value)

  async def set_send_code_when_idle(self, value):
    """Sets whether to send a code when idle

    :param value: A bool"""
    return await self._simple_set("Send Code When Idle", value)

  async def set_application_keypad_allowed(self, value):
    """Sets whether the terminal may be placed in application keypad mode

    :param value: A bool"""
    return await self._simple_set("Application Keypad Allowed", value)

  async def set_place_prompt_at_first_column(self, value):
    """Sets whether the prompt should always begin at the first column (requires shell integration)

    :param value: A bool"""
    return await self._simple_set("Place Prompt at First Column", value)

  async def set_show_mark_indicators(self, value):
    """Sets whether mark indicators should be visible

    :param value: A bool"""
    return await self._simple_set("Show Mark Indicators", value)

  async def set_idle_code(self, value):
    """Sets the ASCII code to send on idle

    :param value: An int in 0...255"""
    return await self._simple_set("Idle Code", value)

  async def set_idle_period(self, value):
    """Sets how often to send a code when idle

    :param value: A float at least 0"""
    return await self._simple_set("Idle Period", value)

  async def set_unicode_version(self, value):
    """Sets the unicode version for wcwidth

    :param value: A bool"""
    return await self._simple_set("Unicode Version", value)

  async def set_cursor_type(self, value):
    """Sets the cursor type

    :param value: CURSOR_TYPE_xxx"""
    return await self._simple_set("Cursor Type", value)

  async def set_thin_strokes(self, value):
    """Sets whether thin strokes are used.

    :param value: THIN_STROKES_SETTING_xxx"""
    return await self._simple_set("Thin Strokes", value)

  async def set_unicode_normalization(self, value):
    """Sets the unicode normalization form to use

    :param value: UNICODE_NORMALIZATION_xxx"""
    return await self._simple_set("Unicode Normalization", value)

  async def set_character_encoding(self, value):
    """Sets the character encoding

    :param value: CHARACTER_ENCODING_xxx"""
    return await self._simple_set("Character Encoding", value)

  async def set_left_option_key_sends(self, value):
    """Sets the behavior of the left option key.

    :param value: OPTION_KEY_xxx"""
    return await self._simple_set("Option Key Sends", value)

  async def set_right_option_key_sends(self, value):
    """Sets the behavior of the right option key.

    :param value: OPTION_KEY_xxx"""
    return await self._simple_set("Right Option Key Sends", value)


class Profile(WriteOnlyProfile):
  """Represents a session's current profile settings."""
  CURSOR_TYPE_UNDERLINE = 0
  CURSOR_TYPE_VERTICAL = 1
  CURSOR_TYPE_BOX = 2

  THIN_STROKES_SETTING_NEVER = 0
  THIN_STROKES_SETTING_RETINA_DARK_BACKGROUNDS_ONLY = 1
  THIN_STROKES_SETTING_DARK_BACKGROUNDS_ONLY = 2
  THIN_STROKES_SETTING_ALWAYS = 3
  THIN_STROKES_SETTING_RETINA_ONLY = 4

  UNICODE_NORMALIZATION_NONE = 0
  UNICODE_NORMALIZATION_NFC = 1
  UNICODE_NORMALIZATION_NFD = 2
  UNICODE_NORMALIZATION_HFSPLUS = 3

  CHARACTER_ENCODING_UTF_8 = 4

  OPTION_KEY_NORMAL = 0
  OPTION_KEY_META = 1
  OPTION_KEY_ESC = 2

  def __init__(self, session_id, connection, get_profile_property_response):
    super().__init__(session_id, connection)
    self.connection = connection
    self.session_id = session_id
    self.__props = {}
    for prop in get_profile_property_response.properties:
      self.__props[prop.key] = json.loads(prop.json_value)

  async def _simple_get(self, key):
    return self.__props[key]

  async def _color_get(self, key):
    try:
      c = Color()
      c.from_dict(self.__props[key])
      return c
    except:
      return None

  async def get_foreground_color(self):
    """Returns the foreground color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Foreground Color")

  async def get_background_color(self):
    """Returns the background color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Background Color")

  async def get_bold_color(self):
    """Returns the bold text color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Bold Color")

  async def get_link_color(self):
    """Returns the link color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Link Color")

  async def get_selection_color(self):
    """Returns the selection background color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Selection Color")

  async def get_selected_text_color(self):
    """Returns the selection text color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Selected Text Color")

  async def get_cursor_color(self):
    """Returns the cursor color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Cursor Color")

  async def get_cursor_text_color(self):
    """Returns the cursor text color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Cursor Text Color")

  async def get_ansi_0_color(self):
    """Returns the ANSI 0 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 0 Color")

  async def get_ansi_1_color(self):
    """Returns the ANSI 1 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 1 Color")

  async def get_ansi_2_color(self):
    """Returns the ANSI 2 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 2 Color")

  async def get_ansi_3_color(self):
    """Returns the ANSI 3 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 3 Color")

  async def get_ansi_4_color(self):
    """Returns the ANSI 4 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 4 Color")

  async def get_ansi_5_color(self):
    """Returns the ANSI 5 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 5 Color")

  async def get_ansi_6_color(self):
    """Returns the ANSI 6 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 6 Color")

  async def get_ansi_7_color(self):
    """Returns the ANSI 7 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 7 Color")

  async def get_ansi_8_color(self):
    """Returns the ANSI 8 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 8 Color")

  async def get_ansi_9_color(self):
    """Returns the ANSI 9 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 9 Color")

  async def get_ansi_10_color(self):
    """Returns the ANSI 10 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 10 Color")

  async def get_ansi_11_color(self):
    """Returns the ANSI 11 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 11 Color")

  async def get_ansi_12_color(self):
    """Returns the ANSI 12 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 12 Color")

  async def get_ansi_13_color(self):
    """Returns the ANSI 13 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 13 Color")

  async def get_ansi_14_color(self):
    """Returns the ANSI 14 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 14 Color")

  async def get_ansi_15_color(self):
    """Returns the ANSI 15 color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Ansi 15 Color")

  async def get_smart_cursor_color(self):
    """Returns the smart cursor color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Smart Cursor Color")

  async def get_tab_color(self):
    """Returns the tab color.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Tab Color")

  async def get_underline_color(self):
    """Returns the underline color.

    :returns: An iterm2.profile.Color or None"""
    return await self._color_get("Underline Color")

  async def get_cursor_guide_color(self):
    """Returns the cursor guide color. The alpha value is respected.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Cursor Guide Color")

  async def get_badge_color(self):
    """Returns the badge color. The alpha value is respected.

    :returns: An iterm2.profile.Color"""
    return await self._color_get("Badge Color")

  async def get_name(self):
    """Returns the name.

    :returns: A string"""
    return await self._simple_get("Name")

  async def get_badge_text(self):
    """Returns the badge text.

    :returns: An iterm2.profile.Color"""
    return await self._simple_get("Badge Text")

  async def get_answerback_string(self):
    """Returns the answerback string.

    :returns: A string"""
    return await self._simple_get("Answerback String")

  async def get_use_cursor_guide(self):
    """Returns whether the cursor guide should be used.

    :returns: A boolean"""
    return await self._simple_get("Use Cursor Guide")

  async def get_use_tab_color(self):
    """Returns whether the tab color should be used.

    :returns: A string"""
    return await self._simple_get("Use Tab Color")

  async def get_use_underline_color(self):
    """Returns the underline color.

    :returns: An iterm2.profile.Color"""
    return await self._simple_get("Use Underline Color")

  async def get_smart_cursor_color(self):
    """Returns the smart cursor text color.

    :returns: A string"""
    return await self._simple_get("Smart Cursor Color")

  async def get_minimum_contrast(self):
    """Returns the minimum contrast.

    :returns: A float in 0 to 1"""
    return await self._simple_get("Minimum Contrast")

  async def get_cursor_boost(self):
    """Returns the cursor boost level.

    :returns: A float in 0 to 1"""
    return await self._simple_get("Cursor Boost")

  async def get_blinking_cursor(self):
    """Returns whether the cursor blinks.

    :returns: A bool"""
    return await self._simple_get("Blinking Cursor")

  async def get_use_bold_font(self):
    """Returns whether to use the bold variant of the font for bold text.

    :returns: A bool"""
    return await self._simple_get("Use Bold Font")

  async def get_ascii_ligatures(self):
    """Returns whether ligatures should be used for ASCII text.

    :returns: A bool"""
    return await self._simple_get("ASCII Ligatures")

  async def get_non_ascii_ligatures(self):
    """Returns whether ligatures should be used for non-ASCII text.

    :returns: A bool"""
    return await self._simple_get("Non-ASCII Ligatures")

  async def get_use_bright_bold(self):
    """Returns whether bright colors should be used for bold text.

    :returns: A bool"""
    return await self._simple_get("Use Bright Bold")

  async def get_blink_allowed(self):
    """Returns whether blinking text is allowed.

    :returns: A bool"""
    return await self._simple_get("Blink Allowed")

  async def get_use_italic_font(self):
    """Returns whether italic text is allowed.

    :returns: A bool"""
    return await self._simple_get("Use Italic Font")

  async def get_ambiguous_double_width(self):
    """Returns whether ambiguous-width text should be treated as double-width.

    :returns: A bool"""
    return await self._simple_get("Ambiguous Double Width")

  async def get_horizontal_spacing(self):
    """Returns the fraction of horizontal spacing.

    :returns: A float at least 0"""
    return await self._simple_get("Horizontal Spacing")

  async def get_vertical_spacing(self):
    """Returns the fraction of vertical spacing.

    :returns: A float at least 0"""
    return await self._simple_get("Vertical Spacing")

  async def get_use_non_ascii_font(self):
    """Returns whether to use a different font for non-ASCII text.

    :returns: A bool"""
    return await self._simple_get("Use Non-ASCII Font")

  async def get_transparency(self):
    """Returns the level of transparency.

    :returns: A float between 0 and 1"""
    return await self._simple_get("Transparency")

  async def get_blur(self):
    """Returns whether background blur should be enabled.

    :returns: A bool"""
    return await self._simple_get("Blur")

  async def get_blur_radius(self):
    """Returns the blur radius (how blurry). Requires blur to be enabled.

    :returns: A float between 0 and 30"""
    return await self._simple_get("Blur Radius")

  async def get_background_image_is_tiled(self):
    """Returns whether the background image is tiled (true) or stretched (false)

    :returns: A bool"""
    return await self._simple_get("Background Image Is Tiled")

  async def get_blend(self):
    """Returns tow much the default background color gets blended with the background image.

    :returns: A float in 0 to 1"""
    return await self._simple_get("Blend")

  async def get_sync_title(self):
    """Returns whether the profile name stays in the tab title, even if changed by an escape sequence.

    :returns: A bool"""
    return await self._simple_get("Sync Title")

  async def get_disable_window_resizing(self):
    """Returns whether the terminal can resize the window with an escape sequence.

    :returns: A bool"""
    return await self._simple_get("Disable Window Resizing")

  async def get_only_the_default_bg_color_uses_transparency(self):
    """Returns whether window transparency shows through non-default background colors.

    :returns: A bool"""
    return await self._simple_get("Only The Default BG Color Uses Transparency")

  async def get_ascii_anti_aliased(self):
    """Returns whether ASCII text is anti-aliased.

    :returns: A bool"""
    return await self._simple_get("ASCII Anti Aliased")

  async def get_non_ascii_anti_aliased(self):
    """Returns whether non-ASCII text is anti-aliased.

    :returns: A bool"""
    return await self._simple_get("Non-ASCII Anti Aliased")

  async def get_scrollback_lines(self):
    """Returns the number of scrollback lines.

    :returns: An int at least 0"""
    return await self._simple_get("Scrollback Lines")

  async def get_unlimited_scrollback(self):
    """Returns whether the scrollback buffer's length is unlimited.

    :returns: A bool"""
    return await self._simple_get("Unlimited Scrollback")

  async def get_scrollback_with_status_bar(self):
    """Returns whether text gets appended to scrollback when there is an app status bar

    :returns: A bool"""
    return await self._simple_get("Scrollback With Status Bar")

  async def get_scrollback_in_alternate_screen(self):
    """Returns whether text gets appended to scrollback in alternate screen mode

    :returns: A bool"""
    return await self._simple_get("Scrollback in Alternate Screen")

  async def get_mouse_reporting(self):
    """Returns whether mouse reporting is allowed

    :returns: A bool"""
    return await self._simple_get("Mouse Reporting")

  async def get_mouse_reporting_allow_mouse_wheel(self):
    """Returns whether mouse reporting reports the mouse wheel's movements.

    :returns: A bool"""
    return await self._simple_get("Mouse Reporting allow mouse wheel")

  async def get_allow_title_reporting(self):
    """Returns whether the session title can be reported

    :returns: A bool"""
    return await self._simple_get("Allow Title Reporting")

  async def get_allow_title_setting(self):
    """Returns whether the session title can be changed by escape sequence

    :returns: A bool"""
    return await self._simple_get("Allow Title Setting")

  async def get_disable_printing(self):
    """Returns whether printing by escape sequence is disabled.

    :returns: A bool"""
    return await self._simple_get("Disable Printing")

  async def get_disable_smcup_rmcup(self):
    """Returns whether alternate screen mode is disabled

    :returns: A bool"""
    return await self._simple_get("Disable Smcup Rmcup")

  async def get_silence_bell(self):
    """Returns whether the bell makes noise.

    :returns: A bool"""
    return await self._simple_get("Silence Bell")

  async def get_bm_growl(self):
    """Returns whether notifications should be shown.

    :returns: A bool"""
    return await self._simple_get("BM Growl")

  async def get_send_bell_alert(self):
    """Returns whether notifications should be shown for the bell ringing

    :returns: A bool"""
    return await self._simple_get("Send Bell Alert")

  async def get_send_idle_alert(self):
    """Returns whether notifications should be shown for becoming idle

    :returns: A bool"""
    return await self._simple_get("Send Idle Alert")

  async def get_send_new_output_alert(self):
    """Returns whether notifications should be shown for new output

    :returns: A bool"""
    return await self._simple_get("Send New Output Alert")

  async def get_send_session_ended_alert(self):
    """Returns whether notifications should be shown for a session ending

    :returns: A bool"""
    return await self._simple_get("Send Session Ended Alert")

  async def get_send_terminal_generated_alerts(self):
    """Returns whether notifications should be shown for escape-sequence originated notifications

    :returns: A bool"""
    return await self._simple_get("Send Terminal Generated Alerts")

  async def get_flashing_bell(self):
    """Returns whether the bell should flash the screen

    :returns: A bool"""
    return await self._simple_get("Flashing Bell")

  async def get_visual_bell(self):
    """Returns whether a bell should be shown when the bell rings

    :returns: A bool"""
    return await self._simple_get("Visual Bell")

  async def get_close_sessions_on_end(self):
    """Returns whether the session should close when it ends.

    :returns: A bool"""
    return await self._simple_get("Close Sessions On End")

  async def get_prompt_before_closing(self):
    """Returns whether the session should prompt before closign

    :returns: A bool"""
    return await self._simple_get("Prompt Before Closing 2")

  async def get_session_close_undo_timeout(self):
    """Returns tmount of time you can undo closing a session

    :returns: A float at least 0"""
    return await self._simple_get("Session Close Undo Timeout")

  async def get_reduce_flicker(self):
    """Returns whether the flicker fixer is on.

    :returns: A bool"""
    return await self._simple_get("Reduce Flicker")

  async def get_send_code_when_idle(self):
    """Returns whether to send a code when idle

    :returns: A bool"""
    return await self._simple_get("Send Code When Idle")

  async def get_application_keypad_allowed(self):
    """Returns whether the terminal may be placed in application keypad mode

    :returns: A bool"""
    return await self._simple_get("Application Keypad Allowed")

  async def get_place_prompt_at_first_column(self):
    """Returns whether the prompt should always begin at the first column (requires shell integration)

    :returns: A bool"""
    return await self._simple_get("Place Prompt at First Column")

  async def get_show_mark_indicators(self):
    """Returns whether mark indicators should be visible

    :returns: A bool"""
    return await self._simple_get("Show Mark Indicators")

  async def get_idle_code(self):
    """Returns the ASCII code to send on idle

    :returns: An int in 0...255"""
    return await self._simple_get("Idle Code")

  async def get_idle_period(self):
    """Returns how often to send a code when idle

    :returns: A float at least 0"""
    return await self._simple_get("Idle Period")

  async def get_unicode_version(self):
    """Returns the unicode version for wcwidth

    :returns: A bool"""
    return await self._simple_get("Unicode Version")

  async def get_cursor_type(self):
    """Returns the cursor type

    :returns: CURSOR_TYPE_xxx"""
    return await self._simple_get("Cursor Type")

  async def get_thin_strokes(self):
    """Returns whether thin strokes are used.

    :returns: THIN_STROKES_SETTING_xxx"""
    return await self._simple_get("Thin Strokes")

  async def get_unicode_normalization(self):
    """Returns the unicode normalization form to use

    :returns: UNICODE_NORMALIZATION_xxx"""
    return await self._simple_get("Unicode Normalization")

  async def get_character_encoding(self):
    """Returns the character encoding

    :returns: CHARACTER_ENCODING_xxx"""
    return await self._simple_get("Character Encoding")

  async def get_left_option_key_sends(self):
    """Returns the behavior of the left option key.

    :returns: OPTION_KEY_xxx"""
    return await self._simple_get("Option Key Sends")

  async def get_right_option_key_sends(self):
    """Returns the behavior of the right option key.

    :returns: OPTION_KEY_xxx"""
    return await self._simple_get("Right Option Key Sends")


class Color:
  """Describes a color."""
  def __init__(self, r=0, g=0, b=0, a=0, color_space="sRGB"):
    """Create a color.

      r: Red, in 0-255
      g: Green, in 0-255
      b: Blue, in 0-255
      a: Alpha, in 0-255
      color_space: The color space. Only sRGB is supported currently."""
    self.__red = r
    self.__green = g
    self.__blue = b
    self.__alpha = a
    self.__color_space = color_space

  def __repr__(self):
    return "({},{},{},{} {})".format(
        round(255 * self.red),
        round(255 * self.green),
        round(255 * self.blue),
        round(255 * self.alpha),
        self.color_space)

  @property
  def red(self):
    return self.__red

  @red.setter
  def red(self, value):
    self.__red = value

  @property
  def green(self):
    return self.__green

  @green.setter
  def green(self, value):
    self.__green = value

  @property
  def blue(self):
    return self.__blue

  @blue.setter
  def blue(self, value):
    self.__blue = value

  @property
  def alpha(self):
    return self.__alpha

  @alpha.setter
  def alpha(self, value):
    self.__alpha = value

  @property
  def color_space(self):
    return self.__color_space

  @color_space.setter
  def color_space(self, value):
    self.__color_space = value

  def get_dict(self):
    return {
        "Red Component": self.red,
        "Green Component": self.green,
        "Blue Component": self.blue,
        "Alpha Component": self.alpha,
        "Color Space": self.color_space
        }

  def from_dict(self, dict):
    self.red = float(dict["Red Component"])
    self.green = float(dict["Green Component"])
    self.blue = float(dict["Blue Component"])
    if "Alpha Component" in dict:
      self.alpha = float(dict["Alpha Component"])
    else:
      self.alpha = 1
    if "Color Space" in dict:
      self.color_space = dict["Color Space"]
    else:
      self.color_space = "sRGB"
