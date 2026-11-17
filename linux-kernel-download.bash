#!/usr/bin/env bash
set -euo pipefail
cd /tmp
if [[ "${1:-}" == "build" ]]; then
  rm -rf linux
  git clone --depth 1 --single-branch https://github.com/torvalds/linux.git linux
fi
