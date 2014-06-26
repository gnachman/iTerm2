#!/bin/bash
printf '\e]1337;SetUserVar=%s=%s\a' "$1" `echo -n "$2" | base64`

