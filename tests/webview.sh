#!/bin/bash
_STTY=$(stty -g)      ## Save current terminal setup
stty -echo cbreak
./webview.py $1
stty "$_STTY"            ## Restore terminal settings

