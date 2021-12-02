#!/usr/bin/env bash
#
# TODO: convert to Makefile
#
set -e
cd "$(dirname "$0")"
_err() { echo -e "$0:" "$@" >&2 ; exit 1; }
_realpath() { realpath "$1" 2>/dev/null || echo "$1"; }

export CC=clang
export CXX=clang++

BUILD_DIR=${BUILD_DIR:-out/debug}
DAWN_BUILD=$BUILD_DIR/dawn
ALIB_FILE=$BUILD_DIR/libwgpu.a
SOLIB_FILE=$BUILD_DIR/libwgpu.so

# ---- clean ----
[ "$1" != "-clean" ] || rm -rf $BUILD_DIR

# ---- config ----
if ! [ -f $BUILD_DIR/build.ninja ]; then
  mkdir -p $BUILD_DIR
  cmake -B $BUILD_DIR -G Ninja -DCMAKE_BUILD_TYPE=Debug src
fi

# ---- build ----
# for targets, see: ninja -C $BUILD_DIR -t targets | grep -e '^lib.*\.a:'
ninja -C $BUILD_DIR wgpu1

# ---- create libraries ----

_find_libcxx_a() {
  # find c++ library file
  cat << _END_ > /tmp/hello.cc
#include <iostream>
int main(int argc, const char** argv) {
  std::cout << "hello from " << argv[0] << "\n";
  return 0;
}
_END_
  local CLANG_CMDS=$(clang++ -static -### /tmp/hello.cc 2>&1)
  [ -n "$CLANG_CMDS" ] || clang++ -static -### /tmp/hello.cc # for errors
  local LIBCXX_NAME=c++
  case "$CLANG_CMDS" in
    *'"-lstdc++"'*) LIBCXX_NAME=stdc++ ;;
  esac
  # note: "clang++ -print-file-name=F" prints F if not found
  local LIBCXX_FILE=$(clang++ -print-file-name=lib${LIBCXX_NAME}.a)
  if [ "$LIBCXX_FILE" == "lib${LIBCXX_NAME}.a" ] || [ ! -f "$LIBCXX_FILE" ]; then
    LIBCXX_FILE=
    for v in $CLANG_CMDS; do
      [[ "$v" == '"-L/'* ]] || continue  # [bash-specific]
      # strip quotes
      v="${v:3:$(( ${#v} - 4 ))}"  # [bash-specific]
      # echo "** $(_realpath $v)"
      if [ -f "$v/lib${LIBCXX_NAME}.a" -a -z "$LIBCXX_FILE" ]; then
        LIBCXX_FILE=$(_realpath $v/libstdc++.a)
        break
      fi
    done
    [ -n "$LIBCXX_FILE" ] || _err "Can not find static C++ standard library"
  fi
  echo $LIBCXX_FILE
}

LIBCXX_FILE=$(_find_libcxx_a)
echo "using C++ standard library $LIBCXX_FILE"

# generate linker version script
LDV_FILE=$BUILD_DIR/libwgpu.ldv
cat << _END_ > $LDV_FILE
{
  local: *;
  global: wgpu*;
};
_END_

# Find object files
#
# Note re Dummy.cpp.o: fix "error: duplicate symbol: someSymbolToMakeXCodeHappy".
# Dawn implements the same function in about 10 identical source files.
# Just use the first one we find.
rm -f $BUILD_DIR/prelink.o
DUMMY_CPP_FILES=( $(find $BUILD_DIR -name Dummy.cpp.o) )
OBJ_FILES=( \
  $(find $BUILD_DIR -type f -name '*.o' | grep -v Dummy.cpp.o) \
  "${DUMMY_CPP_FILES[0]}" \
)

# ---- static library ----

echo "create $BUILD_DIR/prelink.o"
ld.lld -r -o $BUILD_DIR/prelink.o \
  --lto-O3 \
  --color-diagnostics \
  --no-call-graph-profile-sort \
  --as-needed \
  --thinlto-cache-dir=$BUILD_DIR/lto.cache \
  --discard-locals \
  --version-script="$LDV_FILE" \
  -z noexecstack \
  -z relro \
  -z now \
  -z defs \
  -z notext \
  "${OBJ_FILES[@]}" \
  "$LIBCXX_FILE"

echo "create archive $ALIB_FILE"
rm -f $ALIB_FILE
llvm-ar crs $ALIB_FILE $BUILD_DIR/prelink.o
rm $BUILD_DIR/prelink.o

echo "optimize $ALIB_FILE"
llvm-objcopy \
  --localize-hidden \
  --strip-unneeded \
  --compress-debug-sections=zlib \
  $ALIB_FILE


# ---- dynamic library ----

echo "create $SOLIB_FILE"
clang++ -shared -o $SOLIB_FILE \
  -fuse-ld=lld \
  -flto=thin \
  -Wl,--lto-O3,--thinlto-cache-dir="$BUILD_DIR"/lto.cache \
  -Werror \
  -nostdlib++ \
  -Wl,--color-diagnostics \
  -Wl,--no-call-graph-profile-sort \
  -Wl,--as-needed \
  -Wl,--compress-debug-sections=zlib \
  -Wl,--discard-locals \
  -Wl,--version-script="$LDV_FILE" \
  -Wl,-z,noexecstack \
  -Wl,-z,relro \
  -Wl,-z,now \
  -Wl,-z,defs \
  -Wl,-z,notext \
  "${OBJ_FILES[@]}" \
  "$LIBCXX_FILE" \
  -ldl -lpthread \
  -lgcc -lgcc_eh \
  -lX11

# ---- print some stats ----

_print_filesize() {
  while [ $# -gt 0 ]; do
    echo -en "$1:\t"
    local Z=$(stat -c "%s" "$1")
    if [ $Z -gt 1048575 ]; then
      awk "BEGIN{printf \"%5.1f MB\n\", $Z / 1048576}"
    elif [ $Z -gt 1023 ]; then
      awk "BEGIN{printf \"%5.1f kB\n\", $Z / 1024}"
    else
      awk "BEGIN{printf \"%5.0f B\n\", $Z}"
    fi
    shift
  done
}

_print_filesize $ALIB_FILE $SOLIB_FILE

GLOBALS_COUNT=$(\
  llvm-objdump --demangle --syms $ALIB_FILE \
  | grep -E '^[a-f0-9]+ g' | wc -l)
echo "$GLOBALS_COUNT global symbols:"
llvm-objdump --demangle --syms $ALIB_FILE \
| grep -E '^[a-f0-9]+ g' | head -n10
echo "For complete list, see:"
echo "  llvm-objdump --demangle --syms $ALIB_FILE"

GLOBALS_COUNT=$(\
  llvm-objdump --demangle --dynamic-syms $SOLIB_FILE \
  | grep -E '^[a-f0-9]+ g' | wc -l)
echo "$GLOBALS_COUNT exported dynamic symbols:"
llvm-objdump --demangle --dynamic-syms $SOLIB_FILE \
| grep -E '^[a-f0-9]+ g' | head -n10
readelf --dyn-syms -D $SOLIB_FILE | head -n10
echo "For complete list, see:"
echo "  llvm-objdump --demangle --dynamic-syms $SOLIB_FILE"

_objdump_dylib() {
  printf "objdump_dylib $1:"
  local OUT=$(\
    llvm-objdump -p "$1" \
    | grep -E 'NEEDED|RUNPATH|RPATH' \
    | awk '{printf $1 " " $2 "\n"}' )
  if [ -n "$OUT" ]; then
    echo
    echo "$OUT"
  else
    echo " (not dynamically linked)"
  fi
}
echo
echo "Runtime requirements:"
_objdump_dylib $SOLIB_FILE
