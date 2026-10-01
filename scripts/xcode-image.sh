#!/usr/bin/env bash
# The xcode-27 job's first step: assert that the runner is macOS 27, and print
# what identifies the image, the Xcode and the SDK. The label names an Xcode and
# not an OS, and the image has changed its base OS before, so the job says what
# it got or fails.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
echo "ImageOS=${ImageOS:-unset}"
echo "ImageVersion=${ImageVersion:-unset}"
echo "RUNNER_ARCH=${RUNNER_ARCH:-unset}"
uname -a
sw_vers
ver="$(sw_vers -productVersion)"
echo "-- xcodebuild -version"
xcodebuild -version
echo "-- xcode-select -p: $(xcode-select -p)"
sdk="$(xcrun --show-sdk-path)"
echo "-- xcrun --show-sdk-path: $sdk"
echo "-- xcrun --show-sdk-version: $(xcrun --show-sdk-version)"
if grep -q 'arm64e\.x1' "$sdk/usr/lib/libSystem.tbd" 2>/dev/null; then
    echo "-- the SDK's libSystem.tbd lists arm64e.x1"
else
    echo "-- the SDK's libSystem.tbd does not list arm64e.x1"
fi
lab_summary "- image: \`${ImageOS:-?}\` \`${ImageVersion:-?}\`, macOS \`$ver\`, $(xcodebuild -version | tr '\n' ' '), SDK \`$sdk\`"
major="${ver%%.*}"
if [ "$major" != 27 ]; then
    echo "::error::the xcode-27 label delivered macOS $ver, not 27"
    exit 1
fi
echo "ok: macOS major version is 27"
