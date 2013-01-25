#!/usr/bin/env python

import sys, time 

def doTest(tests):
    for test, comment in tests:
        sys.stdout.write(test + " ====> ")
        chars = test.split(" ")
        for char in chars:
            if char == "WAIT":
                sys.stdout.flush()
                time.sleep(0.5)
            else:
                char = char.replace("CAN", "\x0e")
                char = char.replace("SUB", "\x1a")
                char = char.replace("ESC", "\x1b")
                char = char.replace("SP", " ")
                sys.stdout.write(char)
        sys.stdout.write("\x1b[m  --- (%s)\n" % comment)
    sys.stdout.write("\n")

hr = "----------------------------------------------------"

print hr
print "Test1: various prefix & intermediate bytes"
print hr
tests1 = [
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
doTest(tests1)

print hr
print "Test2: continuous parsing"
print hr
tests2 = [
    [ "ESC [ WAIT 3 1 m a b c",
      "red colored text 'abc'" ],
    [ "ESC [ > > WAIT < ? 3 1 SP m a b c",
      "normal styled text 'abc'" ],
    [ "ESC [ 3 WAIT 1 m a b c",
      "red colored text 'abc'" ],
    [ "ESC [ 3 1 % WAIT $ m a b c",
      "normal styled text 'abc'" ],
]
doTest(tests2)

print hr
print "Test3: long parameters"
print hr
tests3 = [
    [ "ESC [ ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; m",
      "expected to be skipped" ],
    [ "ESC [ 1 ; 2 ; 3 ; 4 ; 5 ; 6 ; 7 ; 8 ; 9 ; 10 ; 11 ; 12 ; 13 ; 14 ; 15 ; 16 ; 17 ; 18 m",
      "expected to be skipped" ],
    [ "ESC [ 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 ; m",
      "expected to be skipped" ],
]
doTest(tests3)


