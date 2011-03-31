# iTerm2 with "Mouse in the Shell" technology
## Extremely alpha.

[Screencast](http://vimeo.com/21690922)

Ever wanted to be able to click on paths to open things in a shell?
Well, now you can! It'll even open it to the right line if
it looks like filename.ext:line_number.

## Instructions
Currently requires either MacVim or Textmate to be installed.
Just download (or build your own, if you're paranoid), and off you go!

## Cavets
* Does not work with paths with spaces (for now).
* Only works when paths clicked are resolvable from the current directory in the shell (for now)
* No configuration options (for now).

## TODO
* Make paths work even after the directory has been changed.
* Configuration options
* More modifier keys: e.g.,
  * Shift + Command + Click on a folder does `cd <dir>; ls`
  * Shift + Command + Click on a foo_spec.rb:88 does `spec foo_spec.rb -l 88`

Jack Chen (chendo)
