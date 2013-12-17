#!/bin/bash
#
# This file tests the growl OSC escapes handling. Newlines embedded in the
# argument indicate the first component should be used as a custom alert
# title, unless the title or message would be empty, in which case the
# argument is used as the message text as before. Other newlines are left
# as-is in the message text. 

# Alert
# Session Shell #1: Line0
echo -en "\033]9;Line0\007"

# Alert
# Session Shell #1: Line0
echo -en "\033]9;Line0\n\007"

# Alert
# Session Shell #1:
# Line1
echo -en "\033]9;\nLine1\007"

# Alert
# Session Shell #1:
# Line1
# Line2
echo -en "\033]9;\nLine1\nLine2\007"

# Custom Title
# Session Shell #1: Line0
echo -en "\033]9;Custom Title\nLine0\007"

# Custom Title
# Session Shell #1: Line0
# Line1
echo -en "\033]9;Custom Title\nLine0\nLine1\007"

# Custom Title
# Session Shell #1:
# Line1
# Line2
echo -en "\033]9;Custom Title\n\nLine1\nLine2\007"
