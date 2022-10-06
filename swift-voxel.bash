#!/usr/bin/env bash
set -exo pipefail
cd "${HOME}"
if [[ "${*}" =~ "prep" ]]; then
  [[ ! -d SwiftVoxel ]] && git clone https://github.com/claygarrett/SwiftVoxel.git
fi
if [[ "${*}" =~ "build" ]]; then
  cd SwiftVoxel
  SIM_VER="$(xcrun simctl list --json devices available | grep name | grep Pro | head -1 | cut -d'"' -f 4)"
  xcodebuild -workspace SwiftVoxel.xcworkspace -derivedDataPath /tmp/ -scheme SwiftVoxel -destination "platform=iOS Simulator,name=${SIM_VER}" build
  SIMID=$(xcrun simctl create test "com.apple.CoreSimulator.SimDeviceType.$(echo ${SIM_VER} | sed 's/ /-/g')")
  xcrun simctl boot "${SIMID}"
  sleep 120
  open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app
  xcrun simctl install test /tmp/Build/Products/Debug-iphonesimulator/SwiftVoxel.app
  BUNDLE_ID="$(defaults read /tmp/Build/Products/Debug-iphonesimulator/SwiftVoxel.app/Info.plist CFBundleIdentifier)"
  xcrun simctl launch test "${BUNDLE_ID}"
  sleep 300 # Sleep 5 minutes to make sure the VM doesn't crash
fi
