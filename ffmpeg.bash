#!/bin/bash
set -euo pipefail
cd "${HOME}"
if [[ "${1:-}" == "prep" ]]; then
  rm -rf ffmpeg
  git clone --depth 1 --branch n4.0 https://github.com/FFmpeg/FFmpeg.git ffmpeg
fi
if [[ "${1:-}" == "build" ]]; then
  cd ffmpeg
  ./configure --disable-autodetect --disable-asm
  if [[ -n "${2:-}" ]]; then
    threads="${2}"
  else
    threads="$(sysctl -n hw.ncpu)"
  fi
  make -j "${threads}"
fi
