#!/bin/bash
# Ramp up, then pause without giving a percentage. The percentage is optional
# for the paused state, so the bar should hold at 60% and turn orange.
for i in $(seq 0 60); do
    printf '\e]9;4;1;%d\a' "$i"
    sleep 0.02
done
sleep 1
printf '\e]9;4;4\a'
sleep 3

# An explicitly invalid percentage is ignored, so nothing should change here.
printf '\e]9;4;4;101\a'
sleep 2
printf '\e]9;4;0\a'
sleep 1

# Pausing with nothing showing gives a small bar instead of an invisible one.
printf '\e]9;4;4\a'
sleep 3
printf '\e]9;4;0\a'
