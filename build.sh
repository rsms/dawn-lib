#!/bin/sh
set -e
cd "$(dirname "$0")"

[ -d depot_tools ] || git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
[ -d dawn ] || git clone https://dawn.googlesource.com/dawn.git

export PATH=$PATH:$PWD/depot_tools

cd dawn
git checkout -d 1fe05467a6da2781ae63b092d336823724a8ae4a
cp scripts/standalone.gclient .gclient
gclient sync
cd ..

nix-shell shell.nix
