#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

WGPU_LIB_DIR=../out/debug
[ -d $WGPU_LIB_DIR ] || WGPU_LIB_DIR=../out/release

C_FLAGS=( \
  -Wall
  -g \
  -std=c11 \
  -I../include \
)

LD_FLAGS=( \
  -fuse-ld=lld \
  -flto \
  -Werror \
  -Wl,--color-diagnostics \
  -Wl,--as-needed \
)

## Optimization flags:
# COMPILE_FLAGS+=( -O3 -march=native )
# LD_FLAGS+=( -Wl,--lto-O3 )
# LD_FLAGS+=( -Wl,--strip-all -Wl,--discard-all )

mkdir -p bin lib obj
clang "${C_FLAGS[@]}" -c hello_triangle.c -o obj/hello_triangle.o

# statically link libwgpu, dynamically link system libs
clang "${LD_FLAGS[@]}" -o bin/hello_triangle \
  obj/hello_triangle.o \
  -Wl,--compress-debug-sections=zlib \
  $WGPU_LIB_DIR/libwgpu.a \
  -lpthread -lX11 -lm -ldl

# dynamically link libwgpu and system libs
cp $WGPU_LIB_DIR/libwgpu.so lib/libwgpu.so
clang "${LD_FLAGS[@]}" -o bin/hello_triangle-sh \
  obj/hello_triangle.o \
  -Wl,--compress-debug-sections=zlib \
  -L./lib -rpath \$ORIGIN/../lib -lwgpu -lm

# statically link libwgpu and system libs
clang "${LD_FLAGS[@]}" -static -o bin/hello_triangle-static \
  obj/hello_triangle.o \
  -Wl,--compress-debug-sections=zlib \
  -L$WGPU_LIB_DIR -lwgpu \
  -lpthread -lm -ldl -lX11 -lxcb -lXau -lXdmcp

# create stripped versions
for f in hello_triangle hello_triangle-sh hello_triangle-static; do
  strip -o bin/$f-stripped bin/$f &
done
wait

# ---- print some stats ----
_objdump_dylib() {
  printf "objdump_dylib $1:"
  local OUT=$(\
    objdump -p "$1" \
    | grep -E 'NEEDED|RUNPATH|RPATH' \
    | awk '{printf "  " $1 " " $2 "\n"}' )
  if [ -n "$OUT" ]; then
    echo
    echo "$OUT"
  else
    echo " (not dynamically linked)"
  fi
}

_objdump_dylib bin/hello_triangle
_objdump_dylib bin/hello_triangle-sh

ls -lh lib/*.so bin/hello_triangle*
