#!/usr/bin/env bash
set -exo pipefail
cd /tmp
# if [[ "${*}" =~ "prep" ]]; then
# fi
if [[ "${*}" =~ "build" ]]; then
  git clone https://github.com/torvalds/linux.git
fi
