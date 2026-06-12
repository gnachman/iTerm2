#!/bin/bash
# Cycle through every kind of progress bar

echo "=== Success (0-100%) ==="
for i in $(seq 0 5 100); do
    printf '\e]9;4;1;%d\a' "$i"
    sleep 0.1
done
sleep 1

echo "=== Error determinate (0-100%) ==="
for i in $(seq 0 5 100); do
    printf '\e]9;4;2;%d\a' "$i"
    sleep 0.1
done
sleep 1

echo "=== Warning (0-100%) ==="
for i in $(seq 0 5 100); do
    printf '\e]9;4;4;%d\a' "$i"
    sleep 0.1
done
sleep 1

echo "=== Indeterminate ==="
printf '\e]9;4;3\a'
sleep 3

echo "=== Error (pulsing) ==="
printf '\e]9;4;2\a'
sleep 3

echo "=== Stop ==="
printf '\e]9;4;0\a'
