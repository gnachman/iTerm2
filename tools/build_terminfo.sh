#!/bin/bash

# This script builds iTerm2's modified terminfo files by starting with the
# system terminfo and adding definitions in Resources/xterm-terminfo-additions.
# This avoids compatibility problems with apps that expect the system terminfo,
# since who knows what version macOS ships with. You probably need to run this
# for each new major version of macos.
# TODO: Do this at runtime.

rm -rf Resources/terminfo
mkdir Resources/terminfo

# These are the terminfo entries that xterm defines intersected with what ships with macOS, minus those that would cause duplication.
terms=( "ansi+enq" "ansi+rep" "dec+sl" "vt220+keypad" "xterm" "xterm+256color" "xterm+app" "xterm+edit" "xterm+kbs" "xterm+pc+edit" "xterm+pcc0" "xterm+pcc1" "xterm+pcc2" "xterm+pcc3" "xterm+pce2" "xterm+pcf0" "xterm+pcf2" "xterm+pcfkeys" "xterm+sm+1006" "xterm+tmux" "xterm+vt+edit" "xterm+x11mouse" "xterm-16color" "xterm-256color" "xterm-88color" "xterm-8bit" "xterm-basic" "xterm-bold" "xterm-color" "xterm-hp" "xterm-new" "xterm-noapp" "xterm-old" "xterm-r5" "xterm-r6" "xterm-sco" "xterm-sun" "xterm-vt220" "xterm-vt52" "xterm-xf86-v44" "xterm-xfree86" "xterms")

cat /dev/null > Resources/xterm-terminfo

# Iterate over the list
for term in "${terms[@]}"; do
  infocmp -x $term >> Resources/xterm-terminfo
  perl -pi -e 'chomp if eof' Resources/xterm-terminfo
  cat Resources/xterm-terminfo-additions >> Resources/xterm-terminfo
done

unset TERMINFO_DIRS

/usr/bin/tic -x -o Resources/terminfo Resources/xterm-terminfo
/usr/bin/tic -x -o Resources/terminfo Resources/tmux-terminfo

export TERMINFO_DIRS=$(pwd)/Resources/terminfo
infocmp -x xterm-256color
