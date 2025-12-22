#!/bin/bash
for i in $(seq 0 100); do
    echo -n -e "\033]9;4;1;$i\a"
    sleep 0.1
done
echo -e "\033]9;4;0\a"
