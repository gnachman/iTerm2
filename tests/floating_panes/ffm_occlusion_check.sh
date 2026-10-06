#!/bin/zsh
# Manual check, with the real pointer, that focus follows mouse respects floating panes.
#
# Needs the dev instance running (make run) with Focus Follows Mouse turned on, and the Python API
# enabled. It opens a window with a floating pane, then moves the pointer:
#   1. over the float          -> the float should have focus (accent outline)
#   2. onto the uncovered tiled pane -> the tiled pane should have focus (neutral outline,
#                                       tiled text not dimmed)
#   3. back over the float     -> the float should have focus again
# and saves a capture of each step. Synthetic input goes only to the dev instance's pid, and only
# while it is frontmost.
#
#   tests/floating_panes/ffm_occlusion_check.sh [output-directory]

set -e
here=${0:A:h}
repo=${here:h:h}
suite=${SUITE:-${repo:t}}
out=${1:-${TMPDIR:-/tmp}/ffm_occlusion_check}
mkdir -p $out
devctl=${TMPDIR:-/tmp}/iterm2-devctl-$USER
if [[ ! -x $devctl || $here/devctl.swift -nt $devctl ]]; then
    swiftc -O $here/devctl.swift -o $devctl
fi
pid=$($devctl devpid $suite)

script=$out/make_float.py
cat > $script <<'EOF'
import asyncio
import iterm2

async def main(connection):
    window = await iterm2.Window.async_create(connection)
    await window.async_set_frame(iterm2.Frame(iterm2.Point(200, 150), iterm2.Size(1000, 700)))
    await asyncio.sleep(0.5)
    await iterm2.MainMenu.async_select_menu_item(connection, "New Floating Pane with Current Profile")
    await asyncio.sleep(1)

iterm2.run_until_complete(main)
EOF
$here/devapi.sh $script

# The window's top left is (200, 150) in the API's coordinates, which have y up from the bottom of
# the main screen; devctl uses y down from the top. Use the window list to find it.
read -r window x y w h rest <<< "$($devctl windows $pid | head -1)"
float_x=$((x + w / 2)); float_y=$((y + h / 2))
tiled_x=$((x + 20)); tiled_y=$((y + h - 40))

step() {
    $devctl activate $pid > /dev/null
    $devctl move $pid $2 $3
    sleep 0.2
    $devctl move $pid $(($2 + 2)) $(($3 + 2))
    sleep 0.5
    $devctl capture $window $out/$1.png
    echo "$1: $out/$1.png"
}
step 1-over-float $float_x $float_y
step 2-over-tiled $tiled_x $tiled_y
step 3-over-float-again $float_x $float_y
