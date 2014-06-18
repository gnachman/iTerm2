tell application "/Users/gnachman/iTerm2/Build/Development/iTerm.app"
        tell the current terminal
                tell the current session
                        set ansi black color to {0, 0, 0}
                        set ansi red color to {32767, 0, 0}
                        set ansi green color to {0, 32767, 0}
                        set ansi yellow color to {32767, 32767, 0}
                        set ansi blue color to {0, 0, 32767}
                        set ansi magenta color to {32767, 0, 32767}
                        set ansi cyan color to {0, 32767, 32767}
                        set ansi white color to {45535, 45535, 45535}
                        set ansi bright black color to {32767, 32767, 32767}
                        set ansi bright red color to {65535, 0, 0}
                        set ansi bright green color to {0, 65535, 0}
                        set ansi bright yellow color to {65535, 65535, 0}
                        set ansi bright blue color to {0, 0, 65535}
                        set ansi bright magenta color to {65535, 0, 65535}
                        set ansi bright cyan color to {0, 65535, 65535}
                        set ansi bright white color to {65535, 65535, 65535}
                end tell
        end tell
end tell

