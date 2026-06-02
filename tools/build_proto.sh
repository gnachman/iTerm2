#!/bin/bash
# Regenerate generated protobuf code (ObjC + Python).
#
# Dependencies:
#   brew install protobuf@21          # arm64 protoc 3.21.x
#   pip3 install mypy-protobuf protobuf
#
# Why protoc 3.21 and nothing newer: the bundled ObjC runtime under
# ThirdParty/ProtobufRuntime/ has GOOGLE_PROTOBUF_OBJC_VERSION=30004 and
# accepts gencode in the [MIN_SUPPORTED=30001 .. 30004] range. protoc 3.19,
# 3.20, and 3.21 all emit gencode 30004; protoc 3.22+ bumps the gencode
# version past what this runtime accepts. The 3.20->21 rename in May 2022
# means the next protoc after 3.21 is "21.x" (libprotoc 21.x), then 22.x.
#
# Why protoc 3.21 also for the Python pass: the Python `protobuf` runtime
# floor for the iTerm2 SDK is 3.7+. protoc 22+ emits Python gencode that
# requires protobuf runtime >= 5.x, which dropped 3.7-3.9. Holding at
# protoc 3.21 keeps the SDK importable on its documented Python floor.
#
# Override the binary if you have it somewhere other than the brew path:
#   PROTOC=/path/to/protoc tools/build_proto.sh

set -e

SOURCE=proto
GENFILES=sources/proto

PROTOC="${PROTOC:-/opt/homebrew/opt/protobuf@21/bin/protoc}"
if [[ ! -x "$PROTOC" ]]; then
  if command -v protoc >/dev/null 2>&1; then
    PROTOC=$(command -v protoc)
  else
    echo "error: protoc 3.21.x required and none found" >&2
    echo "  brew install protobuf@21   # installs to /opt/homebrew/opt/protobuf@21/bin/protoc" >&2
    exit 1
  fi
fi

PROTOC_VER=$("$PROTOC" --version 2>/dev/null | awk '{print $2}')
case "$PROTOC_VER" in
  3.19.*|3.20.*|3.21.*) : ;;
  *)
    echo "error: protoc 3.19.x, 3.20.x, or 3.21.x required (got '$PROTOC_VER' from $PROTOC)" >&2
    echo "  brew install protobuf@21" >&2
    exit 1
    ;;
esac

"$PROTOC" --proto_path="$SOURCE" \
          --objc_out="$GENFILES" \
          --python_out=api/library/python/iterm2/iterm2 \
          --mypy_out=api/library/python/iterm2/iterm2 \
          "$SOURCE"/api.proto
