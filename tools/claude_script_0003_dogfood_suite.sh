#!/bin/bash
# Run the build in an ISOLATED instance for TESTING, so manual/E2E test runs
# can't clobber the Window Projects you accumulate from real dogfooding (or
# reach into your real running shells). Uses iTerm's built-in `-suite <name>`
# arg (parsed in sources/main.m before any UserDefaults access).
#
# Intended split:
#   * REAL DOGFOODING  -> just run the build with NO -suite. It shares prefs,
#                         the iTermServer daemon, and Window Projects storage
#                         with prod (same com.googlecode.iterm2 identity), which
#                         is what you want for living in it day to day.
#   * TESTING          -> this script. `-suite test` gives the instance its own:
#       prefs           NSUserDefaults suites "<suite>" + "<suite>.private"
#       app support     ~/Library/Application Support/<suite>/  (Window Projects
#                       JSON, associations, thumbnails — model is suite-aware)
#       daemon socket   <suite>-daemon-N.socket  (so parked/reattached test
#                       processes can never touch your real running shells)
#
# (XCTest unit tests already isolate themselves to WindowProjects_test.json via
#  the isTesting flag; this is for the manual/launched-build test scenarios.)
#
# Usage:
#   tools/claude_script_0003_dogfood_suite.sh                 # launch suite "test"
#   tools/claude_script_0003_dogfood_suite.sh --seed          # seed the suite's prefs from prod first (so it feels like home)
#   SUITE=scratch tools/claude_script_0003_dogfood_suite.sh   # use a different suite name
#   CONFIG=Deployment tools/claude_script_0003_dogfood_suite.sh   # test against the optimized build
set -u

SUITE="${SUITE:-test}"
CONFIG="${CONFIG:-Development}"
PROD_DOMAIN="com.googlecode.iterm2"

SYMROOT="$(xcodebuild -scheme iTerm2 -showBuildSettings 2>/dev/null | awk -F ' = ' '/^ *SYMROOT/{print $2; exit}')"
APP="$SYMROOT/$CONFIG/iTerm2.app"
BIN="$APP/Contents/MacOS/iTerm2"

if [ ! -x "$BIN" ]; then
  echo "Build not found: $BIN" >&2
  echo "Build it first:  tools/build.sh $CONFIG" >&2
  exit 1
fi

if [ "${1:-}" = "--seed" ]; then
  echo "Seeding suite '$SUITE' from prod settings ($PROD_DOMAIN)…"
  # Public + private defaults domains. iTerm reads "<suite>" and "<suite>.private".
  defaults export "$PROD_DOMAIN"          - | defaults import "$SUITE"          -
  defaults export "$PROD_DOMAIN.private"  - 2>/dev/null | defaults import "$SUITE.private"  - 2>/dev/null
  echo "Done. (Dynamic profiles / scripts live in App Support — to clone those too:"
  echo "  rsync -a ~/Library/Application\\ Support/iTerm2/{DynamicProfiles,Scripts} ~/Library/Application\\ Support/$SUITE/ )"
fi

echo "Launching $CONFIG build with -suite $SUITE (isolated test instance)"
echo "  prefs domain : $SUITE (+ $SUITE.private)"
echo "  app support  : ~/Library/Application Support/$SUITE/"
echo "  daemon socket: $SUITE-daemon-N.socket"
echo "Your real Window Projects (prod / no-suite) are untouched."
exec "$BIN" -suite "$SUITE"
