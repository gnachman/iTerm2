#!/usr/bin/env zsh
# Launch the iTerm2 dev build with interactive reload support.
# Usage: run.sh <app-executable> <build-dir> [app-args...]
#
# Keys:
#   r / R  — rebuild (make Development) and relaunch
#   q / Q  — quit
#   Ctrl-C — quit
#
# Note: if the script is killed with kill -9 (SIGKILL), the terminal may be
# left in raw mode (-echo -icanon). Run `stty sane` to restore normal input.

set -uo pipefail

BOLD=$'\e[1m'
DIM=$'\e[2m'
GREEN=$'\e[32m'
CYAN=$'\e[36m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
RESET=$'\e[0m'

APP_EXEC="$1"
BUILD_DIR="$2"
shift 2
APP_ARGS=("$@")

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"

app_pid=""
saved_stty=$(stty -g)

stop_app() {
  [[ -z "$app_pid" ]] && return
  kill -TERM "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  app_pid=""
}

launch_app() {
  "$APP_EXEC" ${APP_ARGS[@]+"${APP_ARGS[@]}"} &
  app_pid=$!
  print ""
  print "${GREEN}${BOLD}▶  iTerm2 launched${RESET} ${DIM}(PID $app_pid)${RESET}  ${CYAN}r${RESET}${DIM} rebuild+reload${RESET}  ${CYAN}q${RESET}${DIM} quit${RESET}"
}

cleanup() {
  trap - EXIT INT TERM
  stop_app
  stty "$saved_stty"
  print ""
  exit 0
}

rebuild_and_reload() {
  stop_app
  print "${YELLOW}⟳  Building…${RESET}"
  if make -C "$PROJECT_DIR" Development BUILD_DIR="$BUILD_DIR"; then
    print "${GREEN}✓  Build succeeded${RESET}"
    launch_app
  else
    print "${RED}✗  Build failed — fix errors and press r to retry${RESET}"
  fi
}

trap cleanup INT TERM EXIT

stty -echo -icanon min 1 time 0

launch_app

while true; do
  read -rk1 key
  case "$key" in
    r|R) rebuild_and_reload ;;
    q|Q) cleanup ;;
  esac
done
