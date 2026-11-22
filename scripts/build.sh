#!/bin/bash
# Runs the unit tests, builds a universal Release app (Intel + Apple silicon),
# ad-hoc signs it and zips it. Output: build/AudioGrab.app and build/AudioGrab.zip
#   SKIP_TESTS=1 scripts/build.sh   build without running tests
#   REGENERATE=1 scripts/build.sh   regenerate the Xcode project from project.yml first (needs xcodegen)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${REGENERATE:-0}" = "1" ]; then
  xcodegen generate
fi

DERIVED="$PWD/build/DerivedData"
mkdir -p build

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  xcodebuild -project AudioGrab.xcodeproj -scheme AudioGrab -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$DERIVED" test
fi

xcodebuild -project AudioGrab.xcodeproj -scheme AudioGrab -configuration Release \
  -derivedDataPath "$DERIVED" ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO build

rm -rf build/AudioGrab.app build/AudioGrab.zip
ditto "$DERIVED/Build/Products/Release/AudioGrab.app" build/AudioGrab.app
codesign --force --deep -s - build/AudioGrab.app
codesign --verify --strict --verbose=2 build/AudioGrab.app
lipo -info build/AudioGrab.app/Contents/MacOS/AudioGrab
(cd build && ditto -c -k --keepParent AudioGrab.app AudioGrab.zip)
echo "Built $(pwd)/build/AudioGrab.app and $(pwd)/build/AudioGrab.zip"
