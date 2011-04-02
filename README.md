# iTerm2 with "Mouse in the Shell"/Trouter technology
## Extremely alpha.

[Screencast](http://vimeo.com/21690922)

Ever wanted to be able to click on paths to open things in a shell?
Well, now you can! Just hold Command and click on the path in the shell.
It'll even open it to the right line if it looks like filename.ext:line_number.

You can also use Command + drag and it will turn it into a draggable
file handle, which you can drop in any OSX app. Pretty rad, no?

## Instructions
Just [Download](https://github.com/chendo/iTerm2/archives/master) (or build your own,
if you're paranoid or you want the newest features), and off you go!

Works with MacVim, Textmate and BBedit (it searches for editor in that
order)

## Operation
* Command + Click opens the file if it is text in
  MacVim/Textmate/BBedit, otherwise opens with associated program.
* Command + Drag gives you a file handle you can drop on any app that
  supports drag and drop (pretty much everything).
* Command + Shift + Click on a directory does `cd <path>; ls`

## Customisation
If you don't use MacVim, Textmate or BBedit or if you want write
specific parsers, you can have the path sent to an external script of
your choice.

`defaults write com.googlecode.iterm2 TrouterPathHandler <path to script>`

The script must be marked executable (`chmod +x <file>`) and it will
receive the full path and the line number (if any) as arguments.

## Cavets
* Does not work with paths with spaces (for now).
* No configuration options (for now).

## TODO
* Make paths work even after the directory has been changed.
* Configuration options
* More modifier keys: e.g.,
  * Shift + Command + Click on a folder does `cd <dir>; ls`
  * Shift + Command + Click on a foo_spec.rb:88 does `spec foo_spec.rb -l 88`
* Native support for other editors (TextWrangler, JEdit, Emacs, Rubymine)
* Quicklook support

## Changelog

- alpha 1:
* Command + Click to open implemented

Jack Chen (@chendo)
