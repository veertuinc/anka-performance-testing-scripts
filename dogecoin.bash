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
  if [[ "$(arch)" == "arm64" ]]; then
    export PATH="/opt/homebrew/opt/openssl@3/bin:$PATH"
    export LDFLAGS="-L/opt/homebrew/opt/openssl@3/lib -L$(brew --prefix)/lib"
    export CPPFLAGS="-I/opt/homebrew/opt/openssl@3/include -I$(brew --prefix)/include"
    EXTRAS="--with-boost-libdir=$(brew --prefix)/lib"
  else
    export PATH="/usr/local/opt/openssl@1.1/bin:$PATH"
    export LDFLAGS="-L/usr/local/opt/openssl@1.1/lib"
    export CXXFLAGS="-I/usr/local/opt/openssl@1.1/include"
  fi
  ./autogen.sh
  ./configure --disable-wallet --without-gui $EXTRAS
  [[ -z "${2}" ]] && THREADS="$(sysctl -n hw.ncpu)" || THREADS="${2}"
  make -j "${THREADS}"
fi