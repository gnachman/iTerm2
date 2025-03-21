# Therm

[![macos-x64](https://github.com/trufae/Therm/actions/workflows/ci.yml/badge.svg)](https://github.com/trufae/Therm/actions/workflows/ci.yml)

Therm is a fork of iTerm2 made by [pancake](https://infosec.exchange/@pancake) with minimalism in mind:

* Toggleable Notch guard on fullscreen windows (CMD+Shift+G)
* Better defaults (hidden tabs, scrollbars and window controls, dark theme, follow mouse, ...)
* Removed tons of barely-used and buggy features, gaining some performance and reducing size
* Fast fullscreen toggling, no animations (CMD+Enter)
* Resize splits with keystrokes (CMD+Shift+HJKL)
* Remove the AutoUpdates (Sparkle framework) and custom ANSI escape codes
* Search entry is now dark and toggleable with CMD+f
* Removed Brodcast, Tmux and SSH client functionality (buggy)
* Solid, non transparent and no blurry effects allowed. Faster, lighter and more readable.
* Added better default lfonts (Agave, Profont, Firacode, ...)
* Support AlwaysOnTop mode (CMD+Shift+F)
* Disable force-touch link previews, smart-paste and print-to-printer anoying features

<center><img src="https://github.com/trufae/Therm/blob/c933b89a4e670bb24a26d3db1a0fb820917f90ec/therm.png" width=50%></center>

## Installation

Download the latest build from the release page, Therm will never do network requests without your consent, so no auto-udpates, nobody in your network need to know which terminal are you using..

So, in order to get Therm installed in your system you can:

### Manual Installation

Find them out in [https://github.com/trufae/Therm/releases](https://github.com/trufae/Therm/releases)

Just drag and drop the .app into the `/Applications` and accept the certificate.

To resign the app with your certificate you can run this:

```
codesign -f -s 'J5PTVY8BHH' Therm.app/Contents/MacOS/Therm
```

### Using Brew

Maybe

```sh
brew install therm
```

### Source Build

To build it from source you just need to run `make run` or `open Therm.xcodeproj`.

## Future

Plan is to continue removing features and optimizing the code to make Therm even faster and cleaner.

* [ ] Keep purging unnecessary features
* [ ] Remove all deprecated APIs uses
* [ ] Update and improve emoji support
* [ ] Support PowerPC and x86-32 macOS

## Settings

Reset your settings to start from scratch with these steps:

```sh
pkill Therm
rm ~/Library/Preferences/com.pancake.therm.plist
```

## Contributions

No plans to sync changes from iTerm2, except for maybe the Metal backend or better emoji support, but the software renderer is really fast and I can probably write a cleaner utf support from scratch.

I really value and appreciate all the work done by the author of <a href="https://iterm2.com">iTerm2</a>, so feel free to check it out and use it if you prefer.

This is an opensource project, under the GPL license, you can contribute by sending patches or filling issues to share your wishes or concerns.

--pancake
