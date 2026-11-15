#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc Snappi/Effects.swift Tests/main.swift -o "$test_dir/images"
"$test_dir/images"
swiftc -parse-as-library Snappi/Effects.swift Snappi/VideoRenderer.swift Tests/VideoChecks.swift -o "$test_dir/video"
"$test_dir/video"
