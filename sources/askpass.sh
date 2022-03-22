#!/bin/bash
# This script is used by laspass via the LPASS_ASKPASS environment variable.
# It notifies iTerm2 that authentication is needed. The (perhaps localized) request is sent.
# The iTerm2 will respond (perhaps) with a password and that is given back to lpass.
echo "[authentication required]" > /dev/stderr
echo -n "$*: " > /dev/stderr
read answer
echo $answer

