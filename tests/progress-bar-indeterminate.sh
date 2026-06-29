#!/bin/bash
# Show the indeterminate (scrolling) progress bar
printf '\e]9;4;3\a'
sleep 5
printf '\e]9;4;0\a'
