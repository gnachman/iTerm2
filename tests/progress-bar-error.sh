#!/bin/bash
# Show the pulsing error state (no percentage)
printf '\e]9;4;2\a'
sleep 5
printf '\e]9;4;0\a'
