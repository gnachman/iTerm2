#!/bin/bash
printf '\e]1337;SetBadgeFormat=%s\a' `echo -n "$1" | base64`
