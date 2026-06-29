#!/bin/bash
# Creates symlinks to the protobuf runtime and generated API files.
# Run this once before building.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PB_RUNTIME="$REPO_ROOT/ThirdParty/ProtobufRuntime"
PB_API="$REPO_ROOT/sources/proto"
TARGET_DIR="$SCRIPT_DIR/Sources/ProtobufRuntime"
INCLUDE_DIR="$TARGET_DIR/include"

mkdir -p "$INCLUDE_DIR"

# Symlink all protobuf runtime .m files
for f in "$PB_RUNTIME"/*.m; do
    name=$(basename "$f")
    ln -sf "$f" "$TARGET_DIR/$name"
done

# Symlink all protobuf runtime .h files into include/
for f in "$PB_RUNTIME"/*.h; do
    name=$(basename "$f")
    ln -sf "$f" "$INCLUDE_DIR/$name"
done

# Symlink generated API protobuf files
ln -sf "$PB_API/Api.pbobjc.m" "$TARGET_DIR/Api.pbobjc.m"
ln -sf "$PB_API/Api.pbobjc.h" "$INCLUDE_DIR/Api.pbobjc.h"

echo "Protobuf symlinks created successfully."
