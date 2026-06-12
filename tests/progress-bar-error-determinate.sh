#!/bin/bash
# Animate an error (red) progress bar from 0 to 100%
for i in $(seq 0 100); do
    printf '\e]9;4;2;%d\a' "$i"
    sleep 0.05
done
sleep 1
printf '\e]9;4;0\a'
