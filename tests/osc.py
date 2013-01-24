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
            elif char == "NUL":
                sys.stdout.write("\x00")
            elif char == "BS":
                sys.stdout.write("\x08")
            elif char == "LF":
                sys.stdout.write("\x0a")
            elif char == "CR":
                sys.stdout.write("\x0d")
            elif char == "CAN":
                sys.stdout.write("\x18")
            elif char == "SUB":
                sys.stdout.write("\x1a")
            elif char == "ESC":
                sys.stdout.write("\x1b")
            elif char == "BEL":
                sys.stdout.write("\x07")
            elif char == "ST":
                sys.stdout.write("\x1b\\")
            elif char == "SP":
                sys.stdout.write(" ")
            else:
                sys.stdout.write(char)
        sys.stdout.write(" (%s)\n" % comment)
        sys.stdout.write("\nPress Any Key...\n")
        sys.stdin.read(1)

hr = "----------------------------------------------------"

print "\x1b]0;*\x1b\\"

print hr
print "Normal OSC"
print hr
tests1 = [
    [ "ESC ] 0 ; a b c BEL", "title string is 'abc'" ],
    [ "ESC ] 0 ; A B C ST", "title string is 'ABC'" ],
    [ "ESC ] ; d e f ST", "title string is 'def'" ],
]
doTest(tests1)

print "\x1b]0;*\x1b\\"

print hr
print "cancel with CAN/SUB"
print hr
tests2 = [
    [ "ESC ] 0 ; g h CAN i BEL", "'i' is emitted and title is '*'" ],
    [ "ESC ] 0 ; G SUB H I ST", "'HI' is emitted and title is still '*'" ],
]
doTest(tests2)

print "\x1b]0;*\x1b\\"

print hr
print "control characters"
print hr
tests3 = [
    [ "ESC ] 0 ; j NUL k BS l BEL", "title is 'j?k?l'" ],
    [ "ESC ] 0 ; BS J K CR L ST", "title is still '?JK?L'" ],
]
doTest(tests3)

print "\x1b]0;*\x1b\\"

print hr
print "broken ST"
print hr
tests4 = [
    [ "ESC ] 0 ; m n o ESC LF", "title is '*'" ],
    [ "ESC ] 0 ; m LF n o ESC a", "title is still '*'" ],
    [ "1 2 3 ESC ] 0 ; m n o ESC [ 2 D 4 5", "'145' is emitted" ],
    [ "ESC ] 0 ; M N O ESC ] M N O ST", "title is 'MNOMNO'" ],
]
doTest(tests4)

print "\x1b]0;*\x1b\\"

print hr
print "broken OSC (only ESC ] P ...)"
print hr
tests4 = [
    [ "ESC ] P a b c d e f g h i", "'hi' is emitted" ],
    [ "ESC ] P A B C D ESC ] E F G H I", "'HI' is emitted" ],
    [ "ESC ] P 1 2 3 4 BEL 5 6 7 8 9", "'56789' is emitted" ],
    [ "ESC ] P 1 2 3 4 5 6 7 8 9", "'89' is emitted" ],
    [ "ESC [ 3 1 m A B C ESC [ m", "Dark blue colored 'ABC' is emitted" ],
]
doTest(tests4)

print "\x1b]0;*\x1b\\"

print hr
print "continuous parsing"
print hr
tests6 = [
    [ "ESC ] 0 ; WAIT p WAIT q WAIT r BEL", "title string is 'pqr'" ],
    [ "ESC ] 0 ; A WAIT B WAIT C ESC a", "title string is still 'pqr'" ],
]
doTest(tests6)


print "done."

