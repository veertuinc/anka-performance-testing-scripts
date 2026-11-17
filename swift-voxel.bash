#!/usr/bin/env bash
set -euo pipefail
cd "${HOME}"

wait_until() {
  local tries="$1"
  local try=0
  shift
  while (( try < tries )); do
    if "$@"; then
      return 0
    fi
    sleep 2
    try=$((try + 1))
  done
  return 1
}

simulator_has_iphone() {
  xcrun simctl list devices available | grep -q 'iPhone'
}

simulator_is_booted() {
  xcrun simctl list devices | grep -F "${SIMID}" | grep -q '(Booted)'
}

if [[ "${*:-}" == *prep* ]]; then
  if [[ ! -d SwiftVoxel ]]; then
    git clone --depth 1 https://github.com/veertuinc/SwiftVoxel.git
  fi
fi

if [[ "${*:-}" == *build* ]]; then
  cd SwiftVoxel
  if ! wait_until 15 simulator_has_iphone; then
    echo "simctl device list stayed empty" >&2
    exit 1
  fi
  SIM_VER="$(xcrun simctl list devices available | sed -n 's/^[[:space:]]*\(iPhone[^(]*\) (.*/\1/p' | grep Pro | head -n 1 | sed 's/[[:space:]]*$//')"
  if [[ -z "${SIM_VER}" ]]; then
    echo "No iPhone Pro simulator is available" >&2
    exit 1
  fi
  xcodebuild -workspace SwiftVoxel.xcworkspace -derivedDataPath /tmp/ -scheme SwiftVoxel \
    -destination "platform=iOS Simulator,name=${SIM_VER}" build
  SIMID="$(xcrun simctl create test "com.apple.CoreSimulator.SimDeviceType.${SIM_VER// /-}" | tr -d '\r')"
  xcrun simctl boot "${SIMID}"
  if ! wait_until 60 simulator_is_booted; then
    echo "simulator did not boot" >&2
    exit 1
  fi
  open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app
  xcrun simctl install test /tmp/Build/Products/Debug-iphonesimulator/SwiftVoxel.app
  BUNDLE_ID="$(defaults read /tmp/Build/Products/Debug-iphonesimulator/SwiftVoxel.app/Info.plist CFBundleIdentifier)"
  xcrun simctl launch test "${BUNDLE_ID}"
  sleep 300
fi
