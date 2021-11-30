#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

# apk add libx11-dev libxrandr-dev
# apk add lld

[ hello_triangle.o -nt hello_triangle.cc ] ||
cc -Wall -std=c11 -c hello_triangle.c -o hello_triangle.o \
  -I../dawn-dest/include

[ gui_glfw.o -nt gui_glfw.cc ] ||
c++ -Wall -std=c++17 -c gui_glfw.cc -o gui_glfw.o \
  -I../dawn-dest/include \
  -I../dawn/third_party/glfw/include \
  -I../dawn/third_party/khronos \
  -I../dawn/src/include \
  -I../dawn/src

DAWN_LIBS=( $(find ../dawn/out/Debug -name '*.a') )
echo "DAWN_LIBS="
for f in "${DAWN_LIBS[@]}"; do
  echo "  $f"
done

# -nostdlib++
# -rdynamic
# -pie -fPIC

c++ \
  -fuse-ld=lld \
  -Werror \
  -m64 \
  -static \
  -Wl,--fatal-warnings \
  -Wl,--build-id \
  -Wl,-z,noexecstack \
  -Wl,-z,relro \
  -Wl,-z,now \
  -Wl,--color-diagnostics \
  -Wl,--no-call-graph-profile-sort \
  -Wl,--gdb-index \
  -Wl,-z,defs \
  -Wl,--as-needed \
  -Wl,--disable-new-dtags \
  -o hello_triangle \
  hello_triangle.o \
  gui_glfw.o \
  "${DAWN_LIBS[@]}"


## attemt to use system ld
# c++ \
#   -Werror \
#   -m64 \
#   -static \
#   -Wl,--fatal-warnings \
#   -Wl,--build-id \
#   -Wl,-z,noexecstack \
#   -Wl,-z,relro \
#   -Wl,-z,now \
#   -Wl,-z,defs \
#   -Wl,--as-needed \
#   -Wl,--disable-new-dtags \
#   -o hello_triangle \
#   hello_triangle.o \
#   gui_glfw.o \
#   "${DAWN_LIBS[@]}"

# libs = -ldl -lpthread -lrt -lX11 -lXcursor -lXinerama -lXrandr
# include_dirs = -I../.. -Igen -Igen/src/include -I../../src/include
#                -Igen/src -I../../src -I../../third_party/khronos
#                -I../../third_party/glfw/include

# notes
#
# vulkan/vulkan.h found in both:
#   ../dawn/third_party/vulkan-deps/vulkan-headers/src/include
#   ../dawn/third_party/khronos

