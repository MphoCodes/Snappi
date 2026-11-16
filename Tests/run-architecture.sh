#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
simulator=${SNAPPI_SIMULATOR_ID:-booted}
architecture=$(uname -m)
xcrun --sdk iphonesimulator swiftc -parse-as-library \
  -target "$architecture-apple-ios17.0-simulator" \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  Snappi/Effects.swift Snappi/VideoRenderer.swift Snappi/MediaRepository.swift \
  Snappi/MediaProcessor.swift Snappi/PhotoLibraryExporter.swift Snappi/CameraState.swift \
  Snappi/CameraCapturing.swift Snappi/CameraViewModel.swift Tests/ArchitectureChecks.swift \
  -o "$test_dir/architecture-checks"
xcrun simctl spawn "$simulator" "$test_dir/architecture-checks"
