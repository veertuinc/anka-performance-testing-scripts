#!/usr/bin/env bash
set -exo pipefail
cd "${HOME}"
if [[ "${*}" =~ "prep" ]]; then
  [[ ! -d SwiftVoxel ]] && git clone https://github.com/claygarrett/SwiftVoxel.git
fi
if [[ "${*}" =~ "build" ]]; then
  cd SwiftVoxel
  xcodebuild -workspace SwiftVoxel.xcworkspace -derivedDataPath /tmp/ -scheme SwiftVoxel -destination 'platform=iOS Simulator,name=iPhone 13 Pro' build
  SIMID=$(xcrun simctl create test "com.apple.CoreSimulator.SimDeviceType.iPhone-13-Pro")
  xcrun simctl boot "${SIMID}"
  sleep 80
  open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app
  xcrun simctl install test /tmp/Build/Products/Debug-iphonesimulator/SwiftVoxel.app
  BUNDLE_ID="$(defaults read /tmp/Build/Products/Debug-iphonesimulator/SwiftVoxel.app/Info.plist CFBundleIdentifier)"
  xcrun simctl launch test "${BUNDLE_ID}"
  sleep 300 # Sleep 5 minutes to make sure the VM doesn't crash
fi
