#!/usr/bin/env bash
#
# TODO: convert to Makefile
#
set -e
cd "$(dirname "$0")"
_err() { echo -e "$0:" "$@" >&2 ; exit 1; }
_realpath() { realpath "$1" 2>/dev/null || echo "$1"; }

DEPS=deps
DEPS_ABS=$PWD/$DEPS

export PATH=$DEPS_ABS/llvm/bin:$PATH
export CC=clang
export CXX=clang++

IS_RELEASE=
OPT_CLEAN=

while [[ $# -gt 0 ]]; do case "$1" in
  -release)
    shift
    IS_RELEASE=1
    BUILD_DIR=${BUILD_DIR:-out/release}
    ;;
  -clean) OPT_CLEAN=1; shift ;;
  -h|-help|--help)
    cat << EOF
usage: $0 [options]
options:
  -release  Create release build instead of debug build
  -clean    Reset any previous build and start from scratch
  -help     Show help on stdout and exit
EOF
    exit 0 ;;
  *) _err "Unexpected argument $1" ;;
esac; done

BUILD_DIR=${BUILD_DIR:-out/debug}
DAWN_BUILD=$BUILD_DIR/dawn
TMPDIR=${TMPDIR:-/tmp}
HOST_SYS=$(uname -s)
HOST_ARCH=$(uname -m)
MACOS_DEPLOYMENT_TARGET=$(\
  awk '/CMAKE_OSX_DEPLOYMENT_TARGET/ { gsub("\\)",""); print $2 }' src/CMakeLists.txt)
ALIB_FILE=$BUILD_DIR/libwgpu.a
DLIB_FILE=$BUILD_DIR/libwgpu.so
[ "$HOST_SYS" != "Darwin" ] || DLIB_FILE=$BUILD_DIR/libwgpu.dylib
PRELINK_FILE=$BUILD_DIR/libwgpu.o
LIB_VERSION=0.0.1        # used for mach-o dylib
LIB_VERSION_COMPAT=0.0.1 # used for mach-o dylib

[ -f $DEPS/configured ] || _err "Project not configured. Please run ./config.sh"

echo "BUILD_DIR=$BUILD_DIR"

# ---- clean ----
[ -z "$OPT_CLEAN" ] || rm -rf $BUILD_DIR

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
  cat << _END_ > $TMPDIR/hello.cc
#include <iostream>
int main(int argc, const char** argv) {
  std::cout << "hello from " << argv[0] << "\n";
  return 0;
}
_END_
  # Ask clang for the args it would use to compile a C++ file.
  # This will tell us if clang is using libc++ or stdlibc++
  local CLANG_CMDS=$(clang++ -static -### $TMPDIR/hello.cc 2>&1)
  [ -n "$CLANG_CMDS" ] || clang++ -static -### $TMPDIR/hello.cc # for errors
  local LIBCXX_NAME=c++
  case "$CLANG_CMDS" in
    *'"-lstdc++"'*) LIBCXX_NAME=stdc++ ;;
  esac

  # try to ask clang to give us the path
  # note: "clang++ -print-file-name=F" prints F if not found
  local LIBCXX_FILE=$(clang++ -print-file-name=lib${LIBCXX_NAME}.a)
  if [ "$LIBCXX_FILE" != "lib${LIBCXX_NAME}.a" -a -f "$LIBCXX_FILE" ]; then
    echo "$(_realpath "$LIBCXX_FILE")"
    return 0
  fi

  # try to searching library paths
  LIBDIRS="$(clang -print-search-dirs | grep libraries: | cut -d= -f2 | cut -d: -f1)"
  # echo "LIBDIRS=$LIBDIRS" >&2
  for dir in $LIBDIRS; do
    LIBCXX_FILE="$dir/lib${LIBCXX_NAME}.a"
    if [ -f "$LIBCXX_FILE" ]; then
      echo "$(_realpath "$LIBCXX_FILE")"
      return 0
    fi
  done

  # try -L arguments clang claims to use
  # echo "CLANG_CMDS=$CLANG_CMDS" >&2
  for v in $CLANG_CMDS; do
    [[ "$v" == '"-L/'* ]] || continue  # [bash-specific]
    # strip quotes
    v="${v:3:$(( ${#v} - 4 ))}"  # [bash-specific]
    # echo "** $(_realpath $v)" >&2
    LIBCXX_FILE="$v/lib${LIBCXX_NAME}.a"
    if [ -f "$LIBCXX_FILE" ]; then
      echo "$(_realpath "$LIBCXX_FILE")"
      return 0
    fi
  done

  # final resort: look in llvm/lib
  LIBCXX_FILE="$DEPS_ABS/llvm/lib/lib${LIBCXX_NAME}.a"
  if [ -f "$LIBCXX_FILE" ]; then
    echo "$(_realpath "$LIBCXX_FILE")"
    return 0
  fi

  _err "Can not find static C++ standard library"
}

LIBCXX_FILE=$(_find_libcxx_a)
echo "using C++ standard library $LIBCXX_FILE"

# generate linker version script
LDV_FILE=$BUILD_DIR/libwgpu.ldv
if [ "$HOST_SYS" = "Linux" ]; then
  cat << _END_ > $LDV_FILE
{
  local: *;
  global: wgpu*;
};
_END_
fi

# Find object files
#
# Note re Dummy.cpp.o: fix "error: duplicate symbol: someSymbolToMakeXCodeHappy".
# Dawn implements the same function in about 10 identical source files.
# Just use the first one we find.
rm -f $PRELINK_FILE
DUMMY_CPP_FILES=( $(find $BUILD_DIR -name Dummy.cpp.o) )
OBJ_FILES=( \
  $(find $BUILD_DIR -type f -name '*.o' | grep -v Dummy.cpp.o) \
  "${DUMMY_CPP_FILES[0]}" \
)

# ---- static library ----

# flags used for all lld invocations
LLD_COMMON_FLAGS=( \
  --color-diagnostics \
  --lto-O3 \
)

# libs needed for both static and dynamic libraries on macOS
MACOS_FRAMEWORKS=( \
  -framework CoreFoundation \
  -framework CoreGraphics \
  -framework QuartzCore \
  -framework IOSurface \
  -framework Metal \
  -framework IOKit \
  -framework Cocoa
)

_mk_alib_linux() {
  # build a prelinked relocatable object
  echo "create $PRELINK_FILE"
  ld.lld -r -o $PRELINK_FILE \
    "${LLD_COMMON_FLAGS[@]}" \
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
    \
    "${OBJ_FILES[@]}" \
    "$LIBCXX_FILE"

  echo "create $ALIB_FILE"
  rm -f $ALIB_FILE
  llvm-ar crs $ALIB_FILE $PRELINK_FILE

  echo "optimize $ALIB_FILE"
  llvm-objcopy \
    --localize-hidden \
    --strip-unneeded \
    --compress-debug-sections=zlib \
    $ALIB_FILE
}


_mk_dlib_linux() {
  echo "create $DLIB_FILE"
  clang++ -shared -o $DLIB_FILE \
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
}


_mk_alib_macos() {
  LIBUNWIND_FILE="$(dirname "$LIBCXX_FILE")/libunwind.a"
  LIBCXXABI_FILE="$(dirname "$LIBCXX_FILE")/libc++abi.a"
  [ -f "$LIBUNWIND_FILE" ] || _err "$LIBUNWIND_FILE not found"
  [ -f "$LIBCXXABI_FILE" ] || _err "$LIBCXXABI_FILE not found"

  # TODO: try this: localize symbols of internal libs by
  # 1. extract objects of LIBCXX using ar x
  # 2. run objcopy to localize all global symbols but "wgpu*"
  # 3. ar crs to create an archive

  # another idea: rename all C++ symbols with a prefix (to avoid duplicate
  # entries if the lib is linked with libc++ later by the user.)

  echo "create $ALIB_FILE"
  # lld (llvm 13) does not yet support prelinking, so we produce an archive instead

  cat << EOF > $ALIB_FILE.mri
create $ALIB_FILE

addlib $LIBCXX_FILE
addlib $LIBUNWIND_FILE
addlib $LIBCXXABI_FILE
addlib $BUILD_DIR/libwgpu1.a
EOF
  for f in $(find "$DAWN_BUILD" -name '*.a'); do
    echo "addlib $f" >> $ALIB_FILE.mri
  done
  echo "save" >> $ALIB_FILE.mri
  echo "end" >> $ALIB_FILE.mri
  # cat $ALIB_FILE.mri
  llvm-ar -M <$ALIB_FILE.mri
  llvm-ranlib "$ALIB_FILE"
}


_mk_dlib_macos() {
  local EXTRA_ARGS=()
  if echo "$LIBCXX_FILE" | grep -q '/libstdc++.a'; then
    EXTRA_ARGS+=( \
      "$LIBCXX_FILE" \
      "$LIBUNWIND_FILE" \
      "$LIBCXXABI_FILE" \
    )
  else
    EXTRA_ARGS=( -lc++ )
  fi

  local SYMS_FILE=$BUILD_DIR/libwgpu.syms
  cat << _END_ > $SYMS_FILE
# this first explicit symbol acts as a test:
# if it is not found, building the dylib will fail with an error.
_wgpuRenderPassEncoderEndPass

# all symbols with the prefix "wgpu" are made public
_wgpu*

# the rest of the symbols are made local/internal
_END_

  echo "create $DLIB_FILE"

  ld64.lld -dylib -o $DLIB_FILE \
    "${LLD_COMMON_FLAGS[@]}" \
    -install_name "@rpath/$(basename "$DLIB_FILE")" \
    -current_version $LIB_VERSION \
    -compatibility_version $LIB_VERSION_COMPAT \
    -cache_path_lto $BUILD_DIR/lto.cache \
    -arch $HOST_ARCH \
    -exported_symbols_list "$SYMS_FILE" \
    -ObjC \
    -macos_version_min $MACOS_DEPLOYMENT_TARGET \
    -platform_version macos $MACOS_DEPLOYMENT_TARGET $MACOS_DEPLOYMENT_TARGET \
    \
    -lc \
    "${OBJ_FILES[@]}" \
    "${MACOS_FRAMEWORKS[@]}" \
    "${EXTRA_ARGS[@]}"

  # clang++ -shared -o $DLIB_FILE \
  #   -fuse-ld=lld \
  #   -flto=thin \
  #   -Werror \
  #   -nostdlib++ \
  #   -fvisibility=hidden \
  #   -Wl,--color-diagnostics \
  #   -Wl,--lto-O3,-cache_path_lto,"$BUILD_DIR"/lto.cache \
  #   "${OBJ_FILES[@]}" \
  #   "${MACOS_FRAMEWORKS[@]}" \
  #   "${EXTRA_ARGS[@]}"

  # -fvisibility=hidden
  # -Wl,-exported_symbols_list,"$SYMS_FILE"

  # try -dead_strip
}


if [ "$HOST_SYS" = "Linux" ]; then
  _mk_alib_linux
  _mk_dlib_linux
elif [ "$HOST_SYS" = "Darwin" ]; then
  _mk_alib_macos
  _mk_dlib_macos
  echo "write $BUILD_DIR/ldflags-macos.txt"
  echo "${MACOS_FRAMEWORKS[@]}" > $BUILD_DIR/ldflags-macos.txt
else
  _err "Library building not implemented for system $HOST_SYS"
fi

# ---- print some stats ----

_print_filesize() {
  while [ $# -gt 0 ]; do
    echo -en "$1:\t"
    local Z
    if [ "$HOST_SYS" = "Darwin" ]; then
      Z=$(stat -f "%z" "$1")
    else
      Z=$(stat -c "%s" "$1")
    fi
    if [ $Z -gt 1073741824 ]; then
      awk "BEGIN{printf \"%5.1f GB\n\", $Z / 1073741824}"
    elif [ $Z -gt 1048575 ]; then
      awk "BEGIN{printf \"%5.1f MB\n\", $Z / 1048576}"
    elif [ $Z -gt 1023 ]; then
      awk "BEGIN{printf \"%5.1f kB\n\", $Z / 1024}"
    else
      awk "BEGIN{printf \"%5.0f B\n\", $Z}"
    fi
    shift
  done
}

_print_filesize $ALIB_FILE $DLIB_FILE

# static library
SYMFILE=$BUILD_DIR/libwgpu.syms
if [ "$HOST_SYS" = "Darwin" ]; then
  llvm-objdump --syms "$ALIB_FILE" | grep -E '^[a-f0-9]+\s+g' > $SYMFILE
else
  llvm-objdump --demangle --syms "$ALIB_FILE" | grep -E '^[a-f0-9]+\s+g' > $SYMFILE
fi
echo "$ALIB_FILE contains" $(cat $SYMFILE | wc -l) "global symbols:"
cat $SYMFILE | head -n10
echo

# dynamic shared library
if [ "$HOST_SYS" = "Darwin" ]; then
  llvm-objdump --syms "$DLIB_FILE" | grep -E '^[a-f0-9]+\s+g' > $SYMFILE
else
  llvm-objdump --demangle --dynamic-syms "$DLIB_FILE" | grep -E '^[a-f0-9]+\s+g' > $SYMFILE
fi
echo "$DLIB_FILE contains" $(cat $SYMFILE | wc -l) "exported dynamic symbols:"
cat $SYMFILE | head -n10
# [ "$HOST_SYS" != "Linux" ] || readelf --dyn-syms -D $DLIB_FILE | head -n10

_objdump_dylib() {
  printf "objdump_dylib $1:"
  local OUT
  OUT=$(\
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
_objdump_dylib $DLIB_FILE
