#!/bin/bash
set -exo pipefail
git clone https://git.ffmpeg.org/ffmpeg.git
cd ffmpeg
git checkout n4.0
./configure --disable-autodetect --disable-asm
[[ -z "${1}" ]] && THREADS=2 || THREADS="${1}"
make -j "${THREADS}"
exit 1