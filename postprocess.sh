#!/bin/sh
set -e
cd "$(dirname "$0")"

BUILD=dawn/out/Debug
DESTDIR=dawn-dest

rm -rf $DESTDIR

mkdir -p $DESTDIR/lib-tmp
find $BUILD -name '*.a' -exec cp '{}' $DESTDIR/lib-tmp/ ';'

mkdir -p $DESTDIR/include
cp -a $BUILD/gen/src/include/dawn $DESTDIR/include/dawn
mv $DESTDIR/include/dawn/webgpu.h $DESTDIR/include/webgpu.h
ln -s ../webgpu.h $DESTDIR/include/dawn/webgpu.h

# get compiler flags
mkdir -p $DESTDIR/etc
_grepprop() { grep -E "$1\s*=" $2 | sed -E 's/^\s*[^ ]+\s*=\s*//g'; }

CFLAGS_COMMON=$(_grepprop cflags $BUILD/obj/examples/CHelloTriangle.ninja)
# TODO: remove -fcrash-diagnostics-dir=../../tools/clang/crashreports from CFLAGS_COMMON

# [disable cflags as they don't contain anything special]
# echo "write $DESTDIR/cflags"
# printf -- "$CFLAGS_COMMON " > $DESTDIR/cflags
# _grepprop cflags_c $BUILD/obj/third_party/gn/glfw/glfw.ninja >> $DESTDIR/cflags

echo "write $DESTDIR/cxxflags"
printf -- "$CFLAGS_COMMON " > $DESTDIR/cxxflags
_grepprop cflags_cc $BUILD/obj/examples/CHelloTriangle.ninja >> $DESTDIR/cxxflags

_grepprop defines $BUILD/obj/examples/CHelloTriangle.ninja > $DESTDIR/defines
# TODO: investigate -D_GLFW_EGL_LIBRARY=\"libEGL.so\" (does glfw try to load this?)

_grepprop ldflags $BUILD/obj/examples/CHelloTriangle.ninja > $DESTDIR/ldflags
# note: ldflags contains -fuse-ld=lld
# make sure ldflags does not contain any "link with library" directive
if grep -q " -l" $DESTDIR/ldflags; then
  echo "$DESTDIR/ldflags contains -l directive!" >&2
  exit 1
fi

# TODO: copy dawn/buildtools/third_party/libc++/trunk/include
#       and  dawn/buildtools/third_party/libc++abi/trunk/include
# to dest as it is what dawn was built with.
# Needed for dawn C++ headers to work correctly when included.
#
# from cflags_cc:
#   -isystem../../buildtools/third_party/libc++/trunk/include
#   -isystem../../buildtools/third_party/libc++abi/trunk/include

echo "libs used for examples/CHelloTriangle:"
_grepprop libs $BUILD/obj/examples/CHelloTriangle.ninja
