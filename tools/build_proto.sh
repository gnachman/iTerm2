#!/bin/bash
SOURCE=proto
GENFILES=sources/proto
tools/protoc --proto_path="$SOURCE" --objc_out="$GENFILES" --python_out=api/library/python/iterm2/iterm2 "$SOURCE"/api.proto
