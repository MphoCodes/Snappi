#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output_dir=${1:-dist}
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
xcodebuild -project Snappi.xcodeproj -scheme Snappi -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$build_dir" \
  CODE_SIGNING_ALLOWED=NO build
app_path="$build_dir/Build/Products/Release-iphonesimulator/Snappi.app"
test -d "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_dir/Snappi-simulator.zip"
(cd "$output_dir" && shasum -a 256 Snappi-simulator.zip > Snappi-simulator.zip.sha256)
printf '\nSimulator package: %s/Snappi-simulator.zip\n' "$output_dir"
