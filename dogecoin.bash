#!/bin/bash
set -exo pipefail
if [[ $(sw_vers) =~ 10\.14 ]]; then
  >&2 echo "10.14 has issues with JDK being needed and brew will not install required packages properly... skipping" 
  exit
fi
cd "${HOME}"
if [[ "${1}" == "prep" ]]; then
  brew install automake libtool boost miniupnpc openssl pkg-config protobuf qt5 libevent berkeley-db
  git clone https://github.com/dogecoin/dogecoin -b 1.14-maint
fi
if [[ "${1}" == "build" ]]; then
  cd dogecoin
  export PATH="/usr/local/opt/openssl@1.1/bin:$PATH"
  export LDFLAGS="-L/usr/local/opt/openssl@1.1/lib"
  export CXXFLAGS="-I/usr/local/opt/openssl@1.1/include"
  ./autogen.sh
  ./configure --disable-wallet --without-gui
  [[ -z "${2}" ]] && THREADS="$(sysctl -n hw.ncpu)" || THREADS="${2}"
  make -j "${THREADS}"
fi