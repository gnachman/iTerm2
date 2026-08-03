On this page you may edit various prompts that are used in the AI features.

## Edit > Engage Artificial Intelligence

This prompt is used when you invoke the menu item **Edit > Engage Artificial Intelligence** (⌘Y). This takes the text that is being edited and replaces it with a terminal command. It could be at the shell prompt (provided you have Shell Integration installed), in the Composer, or in a text field in various other places in the app.

For example, you could open the Composer (⇧⌘.) and write `Remove files whose name contains a vowel`. Then you select `Engage Artificial Intelligence` and it will rewrite your statement as `rm *[aeiou]*`.

The syntax is that of [interpolated strings](https://iterm2.com/documentation-scripting-fundamentals.html#:~:text=References%2C%20below.-,Interpolated%20Strings,-Another%20way%20that). The `shell` and `uname` variables are always defined and are based on the best guess of these settings in your current session. If you use the SSH integration, these should be correct for the remote host. This is done so the answer can be tailored to the system you're using. The prompt takes the form of a shell script, which is a good way to persuade ChatGPT to write a command. The `\(ai.prompt)` is only available when evaluating an interpolated string in the context of AI and it takes the value that you entered in the composer.

## AI Chat

There are numerous prompts for AI Chat in combination with the availability of different features.

An AI chat may be linked with a terminal session and a web browser session, provided the AI provider supports function calling. If the provider does not support function calling (also known as "tool use") then only `AI Chat (no function calling)` will be in effect.

If you set the `Act in Web Browser` chat permission to `Never Allow` then the prompts that include `Browser Access` will not be used.

If both `Run Commands` and `Control Terminal` are set to `Never` then the prompts that include `Full Terminal` will not be used.

If all the terminal-related permissions are set to `Never` then neither `Full Terminal` nor `Read-Only Terminal` prompts will be used.

By process of elimination, you can determine which prompt applies to your situation.

## Code Review System Prompt

When a workspace has a member with the Code Review role, this prompt goes in the system message and tells the agent how to update iTerm2 with its findings.

## Chat List Icon

This prompt asks the AI to draw an SVG icon for a chat just after a title has been chosen for it. The icon is rasterized and shown next to the chat's name in the chat list. The syntax is that of interpolated strings, and `\(ai.subject)` takes the value of the chat's title. The response must contain an SVG document; anything around it is ignored, and if no renderable SVG is found the chat keeps the default icon.
