#!/bin/sh
set -e
cd "$(dirname "$0")"
_err() { echo -e "$0:" "$@" >&2 ; exit 1; }
_has_dynamic_linking() { llvm-objdump -p "$1" | grep -q NEEDED; }

_needcmd() {
  while [ $# -gt 0 ]; do
    if ! command -v "$1" >/dev/null; then
      _err "missing $1 -- please install or use a different shell"
    fi
    shift
  done
}

# _git_dep <dir> <git-url> <git-hash>
_git_dep() {
  local DIR=$1 ; shift
  local GIT_URL=$1 ; shift
  local GIT_TREE=$1 ; shift
  local FORCE=false
  [ "$(cat "$DIR/git-version" 2>/dev/null)" != "$GIT_TREE" ] ||
    return 1
  if [ ! -d "$DIR" ]; then
    git clone "$GIT_URL" "$DIR"
    FORCE=true
  fi
  git -C "$DIR" fetch origin --tags
  local GIT_COMMIT=$(git -C "$DIR" rev-list -n 1 "$GIT_TREE")
  if $FORCE || [ "$(git -C "$DIR" rev-parse HEAD)" != "$GIT_COMMIT" ]; then
    git -C "$DIR" checkout --detach "$GIT_COMMIT" --
    return 0
  fi
  echo "$GIT_TREE" > "$DIR/git-version"
  return 1
}

# check for programs and shell features needed
_needcmd \
  pushd popd basename \
  tar git cmake ninja sha256sum wget python3 \
  clang clang++ llvm-objcopy llvm-ar llvm-objdump


export CC=clang
export CXX=clang++


echo "---------- depot_tools ----------"
_git_dep depot_tools \
  https://chromium.googlesource.com/chromium/tools/depot_tools.git \
  2e486c0d9d44e651a4def1d8397e4dfa1871ee65 || true

export PATH=depot_tools:$PATH
echo "depot_tools installed at ./depot_tools"


echo "---------- dawn ----------"
if _git_dep dawn \
  https://dawn.googlesource.com/dawn.git \
  1fe05467a6da2781ae63b092d336823724a8ae4a
then
  ( export PATH=$PATH:$PWD/depot_tools
    cd dawn
    cp scripts/standalone.gclient .gclient
    echo "Running 'gclient sync' in $PWD"
    gclient sync )
  rm -rf out/debug/dawn out/release/dawn
fi
echo "dawn installed at ./dawn"


echo "---------- test compiler ----------"
TMPDIR=out/cc-test
rm -rf $TMPDIR
mkdir -p $TMPDIR
pushd $TMPDIR >/dev/null

cat << _END_ > hello.c
#include <stdio.h>
int main(int argc, const char** argv) {
  printf("hello from %s\n", argv[0]);
  return 0;
}
_END_

cat << _END_ > hello.cc
#include <iostream>
int main(int argc, const char** argv) {
  std::cout << "hello from " << argv[0] << "\n";
  return 0;
}
_END_

echo "Compile C and C++ test programs with static and dynamic linking:"
set -x
$CC  -Wall -std=c17     -O2         -o hello_c_d  hello.c
$CC  -Wall -std=c17     -O2 -static -o hello_c_s  hello.c
$CXX -Wall -std=gnu++17 -O2         -o hello_cc_d hello.cc
$CXX -Wall -std=gnu++17 -O2 -static -o hello_cc_s hello.cc
set +x
echo "Compile test programs: OK"

echo "Run test programs:"
for f in hello_c_d hello_c_s hello_cc_d hello_cc_s; do
  ./${f}
  strip -o stipped_$f $f
  ./stipped_$f
done
echo "Run test programs: OK"

_has_dynamic_linking hello_c_s  && _err "hello_c_s has dynamic linking!"
_has_dynamic_linking hello_cc_s && _err "hello_cc_s has dynamic linking!"
_has_dynamic_linking hello_c_d  || _err "hello_c_d is statically linked!"
_has_dynamic_linking hello_cc_d || _err "hello_cc_d is statically linked!"
echo "Verified static and dynamic linking with objdump -p {exe}: OK"

popd >/dev/null
echo "Left files in $TMPDIR"
# ls -lh $TMPDIR

echo "All OK -- CC=$CC CXX=$CXX works correctly"


echo "-----------------------------------"
echo "You can run ./build.sh now"
