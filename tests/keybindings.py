#!/usr/bin/env python3

import iterm2

async def main(connection):
    next_char = 'a'
    def c():
        nonlocal next_char
        result = next_char
        next_char = chr(ord(next_char) + 1)
        return ord(result)

    mods = [iterm2.Modifier.OPTION]
    paste_config = iterm2.PasteConfiguration(
            base64=True,
            wait_for_prompts=True,
            tab_transform=iterm2.PasteConfiguration.TabTransform.CONVERT_TO_SPACES,
            tab_stop_size=8,
            delay=0.1,
            chunk_size=128,
            convert_newlines=True,
            remove_newlines=True,
            convert_unicode_punctuation=True,
            escape_for_shell=True,
            remove_controls=True,
            bracket_allowed=False,
            use_regex_substitution=True,
            regex="^x",
            substitution="X")

    bindings = [
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.NEXT_SESSION, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.NEXT_WINDOW, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.PREVIOUS_SESSION, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.PREVIOUS_WINDOW, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SCROLL_END, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SCROLL_HOME, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SCROLL_LINE_DOWN, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SCROLL_LINE_UP, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SCROLL_PAGE_DOWN, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SCROLL_PAGE_UP, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.ESCAPE_SEQUENCE, "[J", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.HEX_CODE, "0x41", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.TEXT, "Hello world", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.IGNORE, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.IR_BACKWARD, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SEND_C_H_BACKSPACE, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SEND_C_QM_BACKSPACE, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SELECT_PANE_LEFT, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SELECT_PANE_RIGHT, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SELECT_PANE_ABOVE, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SELECT_PANE_BELOW, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.DO_NOT_REMAP_MODIFIERS, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.TOGGLE_FULLSCREEN, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.REMAP_LOCALLY, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SELECT_MENU_ITEM, iterm2.MainMenu.Shell.NEW_WINDOW.value, None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.NEW_WINDOW_WITH_PROFILE, "0C783862-E5CB-4FE8-A3BF-C3D3980128BE", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.NEW_TAB_WITH_PROFILE, "0C783862-E5CB-4FE8-A3BF-C3D3980128BE", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SPLIT_HORIZONTALLY_WITH_PROFILE, "0C783862-E5CB-4FE8-A3BF-C3D3980128BE", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SPLIT_VERTICALLY_WITH_PROFILE, "0C783862-E5CB-4FE8-A3BF-C3D3980128BE", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.NEXT_PANE, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.PREVIOUS_PANE, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.NEXT_MRU_TAB, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.MOVE_TAB_LEFT, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.MOVE_TAB_RIGHT, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.RUN_COPROCESS, "/bin/echo hello world", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.FIND_REGEX, "http:.*", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SET_PROFILE, "0C783862-E5CB-4FE8-A3BF-C3D3980128BE", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.VIM_TEXT, "C-c", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.PREVIOUS_MRU_TAB, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.LOAD_COLOR_PRESET, "Light Background", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.PASTE_SPECIAL, paste_config, None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.PASTE_SPECIAL_FROM_SELECTION, paste_config, None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.TOGGLE_HOTKEY_WINDOW_PINNING, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.UNDO, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.MOVE_END_OF_SELECTION_LEFT, iterm2.MoveSelectionUnit.BIG_WORD, None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.MOVE_END_OF_SELECTION_RIGHT, iterm2.MoveSelectionUnit.BIG_WORD, None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.MOVE_START_OF_SELECTION_LEFT, iterm2.MoveSelectionUnit.BIG_WORD, None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.MOVE_START_OF_SELECTION_RIGHT, iterm2.MoveSelectionUnit.BIG_WORD, None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.DECREASE_HEIGHT, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.INCREASE_HEIGHT, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.DECREASE_WIDTH, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.INCREASE_WIDTH, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SWAP_PANE_LEFT, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SWAP_PANE_RIGHT, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SWAP_PANE_ABOVE, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SWAP_PANE_BELOW, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.FIND_AGAIN_DOWN, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.FIND_AGAIN_UP, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.TOGGLE_MOUSE_REPORTING, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.INVOKE_SCRIPT_FUNCTION, "alert(title: \"Hello world\", subtitle: \"Yo\", buttons: [\"OK\", \"Cancel\"])", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.DUPLICATE_TAB, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.MOVE_TO_SPLIT_PANE, "", None, None),
            iterm2.KeyBinding(c(), mods, None, iterm2.BindingAction.SEND_SNIPPET, iterm2.SnippetIdentifier({"guid": "1F835062-BBDE-4ADC-A27C-9A5449E66D80"}), None, None) ]
    await test_profile(connection, bindings)

async def test_profile(connection, bindings):
    app = await iterm2.async_get_app(connection)
    p = await iterm2.Profile.async_get_default(connection)
    d = {}
    for binding in bindings:
        d[binding.key] = binding.encode
    await p.async_set_key_mappings(d)

    p = await iterm2.Profile.async_get_default(connection)

    assert(len(bindings) == len(p.key_mappings))
    for k in p.key_mappings:
        b2 = iterm2.decode_key_binding(k, p.key_mappings[k])
        b = iterm2.decode_key_binding(k, d[k])
        print(b)
        print(b2)
        assert(b == b2)

async def test_global(connection, bindings):
    await iterm2.async_set_global_key_bindings(connection, bindings)

    actual = await iterm2.async_get_global_key_bindings(connection)
    assert(len(actual) == len(bindings))
    for a in actual:
        i = find(bindings, a)
        if bindings[i] == a:
            del bindings[i]
        else:
            print(bindings[i])
            print(a)
            assert(False)
    assert(len(bindings) == 0)

def find(bindings, query):
    i = 0
    for b in bindings:
        if b.character == query.character and b.modifiers == query.modifiers and b.keycode == query.keycode:
            return i
        i += 1
    assert(False)

iterm2.run_until_complete(main)
