#!/bin/bash
set -euo pipefail
project_cwd_repo="$(cd "$(dirname "$0")/.." && pwd)"
project_cwd_tmp="$(mktemp -d "${TMPDIR:-/tmp}/iterm-required-cwd.XXXXXX")"
trap 'rm -rf "$project_cwd_tmp"' EXIT
xcrun clang -Wall -Wextra -Werror -I "$project_cwd_repo/sources/System" \
    "$project_cwd_repo/sources/System/iTermRequiredDirectory.c" \
    "$project_cwd_repo/tests/project_required_directory_test.c" -o "$project_cwd_tmp/tests"
"$project_cwd_tmp/tests"
# Compile the real server's two child-launch functions and RPC codec. Rename only its main;
# dead-strip unrelated daemon services. Suppress two existing SDK/compiler warnings in those sources.
xcrun clang -Werror -Wno-gnu-folding-constant -Wno-deprecated-declarations \
    -DITERM_SERVER -ffunction-sections -Wl,-dead_strip \
    -I "$project_cwd_repo/sources/System" -I "$project_cwd_repo/sources/Tasks" \
    -I "$project_cwd_repo/sources/Logging" -I "$project_cwd_repo/sources/Infrastructure" \
    "$project_cwd_repo/tests/project_required_directory_backends_test.c" \
    "$project_cwd_repo/sources/System/iTermRequiredDirectory.c" \
    "$project_cwd_repo/sources/System/iTermPosixTTYReplacements.c" \
    "$project_cwd_repo/sources/System/iTermResourceLimitsHelper.c" \
    "$project_cwd_repo/sources/Tasks/iTermTTYState.c" \
    "$project_cwd_repo/sources/Tasks/iTermMultiServerProtocol.c" \
    "$project_cwd_repo/sources/Tasks/iTermClientServerProtocol.c" \
    "$project_cwd_repo/sources/Tasks/iTermFileDescriptorServerShared.c" \
    -framework Carbon -o "$project_cwd_tmp/backend-tests"
"$project_cwd_tmp/backend-tests"
