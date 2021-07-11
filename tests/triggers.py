#!/usr/bin/env python3

import iterm2

async def main(connection):
    instant = False
    enabled = True

    triggers = [
        iterm2.AlertTrigger("^AlertTrigger", "Lorem ipsum", instant, enabled),
        iterm2.AnnotateTrigger("^AnnotateTrigger", "Lorem ipsum", instant, enabled),
        iterm2.BellTrigger("^BellTrigger", instant, enabled),
        iterm2.BounceTrigger("^BounceTrigger", iterm2.BounceTrigger.Action.BOUNCE_UNTIL_ACTIVATED, instant, enabled),
        iterm2.CaptureTrigger("^CaptureTrigger", "/bin/true", instant, enabled),
        iterm2.CoprocessTrigger("^CoprocessTrigger", "/bin/true", instant, enabled),
        iterm2.HighlightLineTrigger("^HighlightLineTrigger", iterm2.Color(255, 0, 0), iterm2.Color(0, 255, 0), instant, enabled),
        iterm2.HighlightTrigger("^HighlightTrigger", iterm2.Color(255, 0, 0), iterm2.Color(0, 255, 0), instant, enabled),
        iterm2.HyperlinkTrigger("^HyperlinkTrigger", "https://google.com/", instant, enabled),
        iterm2.InjectTrigger("^InjectTrigger", "xxx", instant, enabled),
        iterm2.MarkTrigger("^MarkTrigger", True, instant, enabled),
        iterm2.MuteCoprocessTrigger("^MuteCoprocessTrigger", "/bin/true", instant, enabled),
        iterm2.PasswordTrigger("^PasswordTrigger", "Dreamhost", "gnachman", instant, enabled),
        iterm2.RPCTrigger("^RPCTrigger", "foo()", instant, enabled),
        iterm2.RunCommandTrigger("^RunCommandTrigger", "/bin/true", instant, enabled),
        iterm2.SendTextTrigger("^SendTextTrigger", "lorem ipsum", instant, enabled),
        iterm2.SetDirectoryTrigger("^SetDirectoryTrigger", "/etc", instant, enabled),
        iterm2.SetHostnameTrigger("^SetHostnameTrigger", "example.com", instant, enabled),
        iterm2.SetTitleTrigger("^SetTitleTrigger", "lorem ipsum", instant, enabled),
        iterm2.SetUserVariableTrigger("^SetUserVariableTrigger", "hello", '"world"', instant, enabled),
        iterm2.ShellPromptTrigger("^ShellPromptTrigger", instant, enabled),
        iterm2.StopTrigger("^StopTrigger", instant, enabled),
        iterm2.UserNotificationTrigger("^UserNotificationTrigger", "lorem ipsum", instant, enabled),
    ]

    all_profiles = await iterm2.Profile.async_get(connection)
    profile = all_profiles[0]
    trigger_dicts = list(map(lambda t: t.encode, triggers))
    await profile.async_set_triggers(trigger_dicts)

    all_profiles = await iterm2.Profile.async_get(connection)
    profile = all_profiles[0]
    trigger_dicts = profile.triggers
    triggers2 = list(map(iterm2.decode_trigger, trigger_dicts))
    for (lhs, rhs) in zip(triggers, triggers2):
        print(lhs)
        print(rhs)
        assert(lhs == rhs)
        print("")

iterm2.run_until_complete(main)
