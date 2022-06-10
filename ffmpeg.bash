#!/bin/bash
set -exo pipefail
if [[ "${1}" == "prep" ]]; then
  git clone https://git.ffmpeg.org/ffmpeg.git
fi
if [[ "${1}" == "build" ]]; then
  cd ffmpeg
  git checkout n4.0
  ./configure --disable-autodetect --disable-asm
  [[ -z "${1}" ]] && THREADS=12 || THREADS="${1}"
  make -j "${THREADS}"
fi