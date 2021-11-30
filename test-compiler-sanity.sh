#!/bin/sh
set -e
_err() { echo -e "$0:" "$@" >&2 ; exit 1; }
_has_dynamic_linking() { objdump -p "$1" | grep -q NEEDED; }
TMPDIR=/tmp/$(basename "$0")

CC=${CC:-clang}
CXX=${CXX:-clang++}

rm -rf $TMPDIR
mkdir $TMPDIR
cd $TMPDIR

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

echo "Left files in $TMPDIR"
ls -lh $TMPDIR

echo "All OK -- CC=$CC CXX=$CXX works correctly"
