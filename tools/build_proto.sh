#!/bin/bash
SOURCE=proto
GENFILES=sources/proto
tools/protoc --proto_path="$SOURCE" --objc_out="$GENFILES" --python_out=api/examples/python "$SOURCE"/api.proto
tools/protoc --proto_path="$SOURCE" --objc_out="$GENFILES" --python_out=api/library/python "$SOURCE"/api.proto
