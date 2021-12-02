#!/usr/bin/env bash
#
# TODO: convert this mess to a Makefile
# TODO: convert this mess to a Makefile
#
set -e
cd "$(dirname "$0")"
_err() { echo -e "$0:" "$@" >&2 ; exit 1; }
_realpath() { realpath "$1" 2>/dev/null || echo "$1"; }

export CC=clang
export CXX=clang++

BUILD_DIR=${BUILD_DIR:-$PWD/out/debug}
DAWN_BUILD=$BUILD_DIR/dawn

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

# (echo ".a libs in $DAWN_BUILD:" && cd $DAWN_BUILD && find . -name '*.a')

# ---- dawn libs ----
# find $DAWN_BUILD -name '*.a'
DAWN_PUB_LIBS=() # wgpu api; public symbols
DAWN_PUB_LIBS+=($DAWN_BUILD/src/dawn/libdawn_proc.a)

DAWN_LIBS=() # dawn implementation; local symbols
DAWN_LIBS+=($DAWN_BUILD/src/common/libdawn_common.a)
DAWN_LIBS+=($DAWN_BUILD/src/dawn/libdawn_headers.a)
DAWN_LIBS+=($DAWN_BUILD/src/dawn/libdawncpp.a)
DAWN_LIBS+=($DAWN_BUILD/src/dawn/libdawncpp_headers.a)
DAWN_LIBS+=($DAWN_BUILD/src/dawn_native/libdawn_native.a)
DAWN_LIBS+=($DAWN_BUILD/src/dawn_platform/libdawn_platform.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/glfw/src/libglfw3.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/tint/src/libtint.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/spirv-tools/source/libSPIRV-Tools.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/spirv-tools/source/opt/libSPIRV-Tools-opt.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/abseil/absl/base/libabsl_base.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/abseil/absl/base/libabsl_raw_logging_internal.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/abseil/absl/base/libabsl_log_severity.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/abseil/absl/base/libabsl_throw_delegate.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/abseil/absl/base/libabsl_spinlock_wait.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/abseil/absl/strings/libabsl_strings.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/abseil/absl/strings/libabsl_str_format_internal.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/abseil/absl/strings/libabsl_strings_internal.a)
DAWN_LIBS+=($DAWN_BUILD/third_party/abseil/absl/numeric/libabsl_int128.a)

# ---- mklib ----
ALIB_FILE=$BUILD_DIR/libwgpu.a
if [ "$BUILD_DIR/libwgpu1.a" -nt "$ALIB_FILE" -o \
     "${DAWN_LIBS[0]}" -nt "$ALIB_FILE" ]
then
  # find c++ library file
  CLANG_CMDS=$(clang++ -static -### src/wgpu.cc 2>&1)
  [ -n "$CLANG_CMDS" ] || clang++ -static -### src/wgpu.cc # for errors
  LIBCXX_NAME=c++
  case "$CLANG_CMDS" in
    *'"-lstdc++"'*) LIBCXX_NAME=stdc++ ;;
  esac
  # note: "clang++ -print-file-name=F" prints F if not found
  LIBCXX_FILE=$(clang++ -print-file-name=lib${LIBCXX_NAME}.a)
  if [ "$LIBCXX_FILE" == "lib${LIBCXX_NAME}.a" ] || [ ! -f "$LIBCXX_FILE" ]; then
    LIBCXX_FILE=
    for v in $CLANG_CMDS; do
      [[ "$v" == '"-L/'* ]] || continue
      # strip quotes
      v="${v:3:$(( ${#v} - 4 ))}"
      # echo "** $(_realpath $v)"
      if [ -f "$v/lib${LIBCXX_NAME}.a" -a -z "$LIBCXX_FILE" ]; then
        LIBCXX_FILE=$(_realpath $v/libstdc++.a)
        break
      fi
    done
    [ -n "$LIBCXX_FILE" ] || _err "Can not find static C++ standard library"
  fi
  echo "using C++ standard library $LIBCXX_FILE"

  MRI_FILE=$BUILD_DIR/libwgpu.mri
  echo "building $ALIB_FILE"
  rm -f $ALIB_FILE
  cat << EOF > $MRI_FILE
create $ALIB_FILE
addlib $BUILD_DIR/libwgpu1.a
addlib $LIBCXX_FILE
EOF
  for f in "${DAWN_PUB_LIBS[@]}"; do
    echo "addlib $f" >> $MRI_FILE
  done
  for f in "${DAWN_LIBS[@]}"; do
    echo "addlib $f" >> $MRI_FILE
  done
  cat << EOF >> $MRI_FILE
save
end
EOF
  cat $MRI_FILE
  llvm-ar -M < $MRI_FILE
  rm $MRI_FILE
  llvm-objcopy --compress-debug-sections=zlib $ALIB_FILE
  # TODO: hide/localize all symbols except those in libwgpu1.a and DAWN_PUB_LIBS

  # ---- print some stats ----
  stat -c "%n: %s B" $ALIB_FILE
  GLOBALS_COUNT=$(llvm-objdump --demangle --syms $ALIB_FILE | grep -E '^[a-f0-9]+ g' | wc -l)
  echo "$GLOBALS_COUNT global symbols:"
  llvm-objdump --demangle --syms $ALIB_FILE | grep -E '^[a-f0-9]+ g' | head -n10
  echo "For complete list, see:"
  echo "  llvm-objdump --demangle --syms $ALIB_FILE"
fi

# OBJCOPY_FLAGS=( --localize-hidden )
# OBJCOPY_FLAGS+=( --globalize-symbol=wgpuDeviceReference )
# OBJCOPY_FLAGS+=( --keep-symbol=wgpuDeviceReference )
# OBJCOPY_FLAGS+=( --strip-unneeded )
# llvm-objcopy "${OBJCOPY_FLAGS[@]}" $ALIB_FILE


# ---- mkdylib ----
SOLIB_FILE=$BUILD_DIR/libwgpu.so
LDV_FILE=$BUILD_DIR/libwgpu.ldv
if [ "$ALIB_FILE" -nt "$SOLIB_FILE" ]; then
  cat << _END_ > $LDV_FILE
{
  local: *;
  global: wgpu*;
};
_END_

  set -x
  clang++ -shared -o $SOLIB_FILE \
    -fuse-ld=lld \
    -flto \
    -Werror \
    -Wl,--color-diagnostics \
    -Wl,--no-call-graph-profile-sort \
    -Wl,-z,noexecstack \
    -Wl,-z,relro \
    -Wl,-z,now \
    -Wl,-z,defs \
    -Wl,--as-needed \
    -Wl,-z,notext \
    -nostdlib++ \
    -Wl,--compress-debug-sections=zlib \
    -Wl,--discard-locals \
    -Wl,--version-script="$LDV_FILE" \
    $BUILD_DIR/CMakeFiles/wgpu1.dir/wgpu.cc.o \
    "$ALIB_FILE" \
    -ldl -lpthread \
    -lgcc -lgcc_eh \
    -lX11
  set +x

  # ---- print some stats ----
  stat -c "%n: %s B" $SOLIB_FILE
  GLOBALS_COUNT=$(\
    llvm-objdump --demangle --dynamic-syms $SOLIB_FILE \
    | grep -E '^[a-f0-9]+ g' | wc -l)
  echo "$GLOBALS_COUNT global dynamic symbols:"
  llvm-objdump --demangle --dynamic-syms $SOLIB_FILE \
  | grep -E '^[a-f0-9]+ g' | head -n20
  readelf --dyn-syms -D $SOLIB_FILE | head -n20
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
fi
