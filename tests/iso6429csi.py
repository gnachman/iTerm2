#!/usr/bin/env python

tests = [
    [ "ESC [ m a b c ESC [ m",
      "normal styled text 'abc'" ],
    [ "ESC [ 3 1 m a b c",
      "red colored text 'abc'" ],
    [ "ESC [ 3 1 ; 1 m a b c",
      "red colored and bold styled text 'abc'" ],
    [ "ESC [ > 3 1 m a b c",
      "normal styled text 'abc'" ],
    [ "ESC [ ? 3 1 m a b c",
      "normal styled text 'abc'" ],
    [ "ESC [ > > < ? 3 1 m a b c",
      "normal styled text 'abc'" ],
    [ "ESC [ > > < ? 3 1 SP m a b c",
      "normal styled text 'abc'" ],
    [ "ESC [ 3 1 ; 4 4 m a b c",
      "red colored text 'abc' with blue background" ],
    [ "ESC [ 3 1 ; > 4 4 m a b c",
      "normal styled text 'abc'" ],
    [ "ESC [ 3 1 ; ; 4 4 m a b c",
      "white colored text 'abc' with blue background" ],
    [ "ESC [ 3 1 : 4 4 m a b c",
      "normal styled text 'abc'" ],
    [ "ESC [ 3 1 : 4 4 > < SP / m a b c",
      "normal styled text 'abc'" ],
    [ "ESC [ > > SUB < ? 3 1 SP m a b c",
      "normal styled text '<?31 mabc'" ],
    [ "ESC [ > > ESC [ 3 1 m a b c",
      "red colored text 'abc'" ],
    ]

import sys
for test, comment in tests:
    sys.stdout.write(test + " ====> ")
    chars = test.split(" ")
    for char in chars:
        char = char.replace("CAN", "\x0e")
        char = char.replace("SUB", "\x1a")
        char = char.replace("ESC", "\x1b")
        char = char.replace("SP", " ")
        sys.stdout.write(char)
    sys.stdout.write("\x1b[m  --- (%s)\n" % comment)

