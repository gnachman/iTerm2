#!/bin/bash
# Note: you must have mypy-protobuf installed.
# pip3 install mypy-protobuf
SOURCE=proto
GENFILES=sources/proto
tools/protoc --proto_path="$SOURCE" --objc_out="$GENFILES" --python_out=api/library/python/iterm2/iterm2 "$SOURCE"/api.proto --mypy_out=api/library/python/iterm2/iterm2
