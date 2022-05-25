#!/bin/bash
set -eo pipefail
# git clone https://github.com/WebKit/WebKit.git WebKit This would take forever
cd WebKit
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
time ./Tools/Scripts/build-webkit --release
