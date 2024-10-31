#!/usr/bin/env bash
set -exo pipefail
cd "${HOME}"
if [[ "${*}" =~ "prep" ]]; then
  # brew install xcodesorg/made/xcodes
  brew tap mobile-dev-inc/tap
  brew install maestro
  # sudo rm -rfv ~/Library/Developer/CoreSimulator/* || true
  # sudo xcodes runtimes install "iOS 17.5"
fi
if [[ "${*}" =~ "build" ]]; then
  # DEVICE_ID=$(sh -c "xcrun simctl create 'iPhone 15 Pro Max' 'iPhone 15 Pro Max' 'com.apple.CoreSimulator.SimRuntime.iOS-17-5'" | tr -d '\r')
  # xcrun --verbose simctl boot ${DEVICE_ID}
  xcrun simctl list --json devices available; sleep 20 # fix a weird bug where xcrun simctl list --json devices available is empty the first run
  SIM_VER="$(xcrun simctl list --json devices available | grep name | grep Pro | head -1 | cut -d'"' -f4)"
  SIMID=$(xcrun simctl create test "com.apple.CoreSimulator.SimDeviceType.$(echo ${SIM_VER} | sed 's/ /-/g')")
  xcrun simctl boot "${SIMID}"
  sleep 120
  echo n | maestro download-samples
  cd ./samples; unzip sample.zip
  open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app
  xcrun --verbose simctl install Booted Wikipedia.app 2>&1
  export MAESTRO_DRIVER_STARTUP_TIMEOUT=60000000
  maestro --verbose test ios-flow.yaml 2>&1
fi
