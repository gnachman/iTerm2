#!/usr/bin/env bash
# iterm2-notify.sh
# Usage: iterm2-notify.sh "Title" "Subtitle" "/path/to/image.png" "Message body"

title=$1
subtitle=$2
image_data=$3
message=$4

# Build the semicolon-delimited param list
params="message=${message};title=${title};subtitle=${subtitle};image=${image_data}"

# Emit the OSC 1337 rich notification (terminated with BEL)
printf "\033]1337;Notification=%s\a" "$params"
