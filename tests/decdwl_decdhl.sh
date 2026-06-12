#!/bin/bash
# Test script for DECDWL (double-width) and DECDHL (double-height) lines.
# Run: bash tests/decdwl_decdhl.sh

ESC=$'\033'

echo "=== DECDWL (double-width lines) ==="
echo "${ESC}#6Double-width text"
echo "Normal width text"
echo "${ESC}#6ABCDEFGHIJKLMNOP"
echo ""

echo "=== DECDHL (double-height lines) ==="
echo "${ESC}#3Double-height BANNER"
echo "${ESC}#4Double-height BANNER"
echo ""

echo "=== Mixed ==="
echo "${ESC}#6Wide line"
echo "Normal line"
echo "${ESC}#3Top half"
echo "${ESC}#4Top half"
echo "Normal again"
echo ""

echo "=== DECSWL (reset to single-width) ==="
echo "${ESC}#6This is wide"
echo "${ESC}#5This is normal again"
echo ""

echo "=== Scrollback test ==="
echo "Scroll down to push DWL lines into history, then scroll back up."
for i in $(seq 1 5); do
    echo "${ESC}#6Scrollback line $i"
done
for i in $(seq 1 30); do
    echo "padding $i"
done
echo "Scroll up to verify DWL lines in scrollback."
