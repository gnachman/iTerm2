#!/usr/bin/env python

import sys, time

_TARGET_BOTH   = 0
_TARGET_ICON   = 1
_TARGET_WINDOW = 2

def settitle(text, target):
    sys.stdout.write("\x1b]%d;%s\x1b\\" % (target, text))
    sys.stdout.flush()
    time.sleep(0.5)

def pushtitle(target):
    sys.stdout.write("\x1b[22;%dt" % target)
    sys.stdout.flush()
    time.sleep(0.5)

def poptitle(target):
    sys.stdout.write("\x1b[23;%dt" % target)
    sys.stdout.flush()
    time.sleep(0.5)

poptitle(_TARGET_BOTH)           # window: 0, icon: 0
settitle("ABC", _TARGET_ICON)    # icon0 -> "ABC"
pushtitle(_TARGET_ICON)          # window: 0, icon: 1
settitle("DEF", _TARGET_WINDOW)  # window0 -> "DEF"
pushtitle(_TARGET_WINDOW)        # window: 1, icon: 1
settitle("GHI", _TARGET_BOTH)    # window1 -> "GHI", icon1 -> "GHI"
pushtitle(_TARGET_BOTH)          # window: 2, icon: 2
settitle("JKL", _TARGET_BOTH)    # window2 -> "JKL", icon2 -> "JKL"
pushtitle(_TARGET_BOTH)          # window: 3, icon: 3
poptitle(_TARGET_BOTH)           # window: 2, icon: 2
poptitle(_TARGET_BOTH)           # window: 2, icon: 2
poptitle(_TARGET_ICON)           # window: 2, icon: 1
poptitle(_TARGET_WINDOW)         # window: 0, icon: 0

print "Icon title should be 'ABC'."
print "Window title should be 'DEF'."

