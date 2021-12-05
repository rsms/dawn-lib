#!/usr/bin/env bash
# TODO: convert to Makefile
set -e
cd "$(dirname "$0")"

export PATH=$PWD/../deps/llvm/bin:$PATH
WGPU_LIB_DIR=../out/debug
[ -d $WGPU_LIB_DIR ] || WGPU_LIB_DIR=../out/release
mkdir -p bin lib obj

C_FLAGS=( ${CFLAGS:-} \
  -Wall
  -g \
  -flto=thin \
  -std=c11 \
  -I../include \
  -march=native \
)

LD_FLAGS=( ${LDFLAGS:-} \
  -fuse-ld=lld \
  -flto=thin -Wl,--lto-O3 \
  -Werror \
  -Wl,--color-diagnostics \
)

LD_FLAGS_DYNAMIC=( "${LD_FLAGS[@]}" -L"$WGPU_LIB_DIR" )
LD_FLAGS_STATIC=( "${LD_FLAGS[@]}" )
LD_FLAGS_STATIC2=( "${LD_FLAGS[@]}" )
case "$(uname -s)" in
Linux)
  cp $WGPU_LIB_DIR/libwgpu.so lib/
  LD_FLAGS_DYNAMIC+=( -lm -rpath \$ORIGIN/../lib )
  LD_FLAGS_STATIC+=( -lm -ldl -lpthread -lX11 )
  LD_FLAGS_STATIC2+=( -lm -ldl -lpthread -lX11 -lxcb -lXau -lXdmcp )
  ;;
Darwin)
  cp $WGPU_LIB_DIR/libwgpu.dylib lib/
  LD_FLAGS_DYNAMIC+=( -rpath @executable_path/../lib )
  LD_FLAGS_STATIC+=( \
    -Wl,--lto-O3,-cache_path_lto,"$PWD"/$WGPU_LIB_DIR/lto.cache \
    $(cat $WGPU_LIB_DIR/ldflags-macos.txt)
  )
  ;;
esac


echo "cc hello_triangle.c"
clang "${C_FLAGS[@]}" -c hello_triangle.c -o obj/hello_triangle.o

# dynamically link libwgpu and system libs
echo "link bin/hello_triangle-sh"
clang "${LD_FLAGS_DYNAMIC[@]}" -o bin/hello_triangle-sh \
  obj/hello_triangle.o \
  -lwgpu \

# statically link libwgpu, dynamically link system libs
echo "link bin/hello_triangle"
clang "${LD_FLAGS_STATIC[@]}" -o bin/hello_triangle \
  obj/hello_triangle.o \
  $WGPU_LIB_DIR/libwgpu.a

# statically link libwgpu and system libs (THIS IS WIP)
if [ "$(uname -s)" = "Linux" ]; then
  echo "link bin/hello_triangle-static"
  clang "${LD_FLAGS_STATIC2[@]}" -static -o bin/hello_triangle-static \
    obj/hello_triangle.o \
    $WGPU_LIB_DIR/libwgpu.a
fi

# create stripped versions
for f in bin/hello_triangle*; do
  strip -o bin/stripped-$(basename $f) $f &
done

# print dynamic links and list files
if [ "$(uname -s)" = "Darwin" ]; then
  if command -v otool >/dev/null; then
    for f in bin/hello_triangle*; do
      echo $f
      llvm-objdump --macho --rpaths $f | awk '(NR>1){print "RPATH " $0}'
      otool -L $f | awk '(NR>1)' | awk \
        '{printf "LINK "}{for (i=1; i<=NF; i++) printf " " $i}{print ""}'
      echo
    done
  fi
else
  for f in bin/hello_triangle*; do
    printf "objdump_dylib $f:"
    OUT=$(\
      llvm-objdump -p "$f" \
      | grep -E 'NEEDED|RUNPATH|RPATH' \
      | awk '{printf "  " $f " " $2 "\n"}' )
    if [ -n "$OUT" ]; then
      echo
      echo "$OUT"
    else
      echo " (not dynamically linked)"
    fi
  done
fi

wait # for strip jobs to finish
ls -lh lib/libwgpu.* bin/*hello_triangle*
