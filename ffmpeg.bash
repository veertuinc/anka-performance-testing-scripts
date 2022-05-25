#!/bin/bash
set -exo pipefail
cd "${HOME}"
if [[ "${1}" == "prep" ]]; then
  git clone https://git.ffmpeg.org/ffmpeg.git
fi
if [[ "${1}" == "build" ]]; then
  cd ffmpeg
  git checkout n4.0
  ./configure --disable-autodetect --disable-asm
  [[ -z "${2}" ]] && THREADS="$(sysctl -n hw.ncpu)" || THREADS="${2}"
  make -j "${THREADS}"
fi