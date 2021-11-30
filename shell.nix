{
  pkgs ? (import <nixpkgs> {}).pkgsMusl
}:
let
  inherit (pkgs) lib;
  llvmPkgs = pkgs.llvmPackages_13;
  stdenv = llvmPkgs.stdenv;
  mkShell = pkgs.mkShell.override { inherit stdenv; };
  hello_c = pkgs.writeText "hello.c" ''
    #include <stdio.h>
    int main() { printf("hello\n"); return 0; }
  '';
  hello_cc = pkgs.writeText "hello.cc" ''
    #include <iostream>
    int main() { std::cout << "hello\n"; return 0; }
  '';
  dawn_gn_args = pkgs.writeText "args.gn" ''
    # List of properties: gn args <out_dir> --list [--short]
    is_debug=true

    # Build process
    #fatal_linker_warnings=false
    dawn_complete_static_libs=true
    is_component_build=false
    libcxx_is_shared=false
    use_glib=false
    use_ozone=false
    dawn_use_angle=false
    use_custom_libcxx=true
    # use_custom_libcxx makes us use a dawn-bundled version of libc++
    # which is likely to be functional.

    # Vulkan
    dawn_enable_vulkan=true
    dawn_enable_vulkan_loader=true
    # dawn_enable_vulkan_loader: Uses our built version of the Vulkan loader on
    # platforms where we can't assume to have one present at the system level.

    # OpenGL (disable)
    dawn_enable_opengles=false
    dawn_enable_desktop_gl=false
    dawn_enable_opengles=false
    tint_build_glsl_writer=false
    tint_build_hlsl_writer=false
    tint_build_msl_writer=false

    # X11
    use_x11=false
    dawn_use_x11=false
    # Indicates if the UI toolkit depends on X11.
    # Enabled by default. Can be disabled if Ozone only build is required and vice-versa.

    # Misc host system
    #use_udev=false
    # libudev usage. This currently only affects the content layer.
    use_sysroot=false
    # sysroot=?
  '';

in mkShell {
  name = "dawn";
  buildInputs = with pkgs; [ # things needed to run the product
    x11
    xorg.libX11
    xorg.libXext
    xorg.libXinerama
    xorg.libXrandr
    xorg.libXcursor
    xorg.libXi
  ];
  nativeBuildInputs = with pkgs; [ # things needed to build the product
    nano
    ninja
    python3
    git
    pkg-config
  ] ++ (with llvmPkgs; [
    clang
    clang-unwrapped
    lld
    llvm
  ]);
  hardeningDisable = [ "all" ];
  shellHook = ''
    export EDITOR=nano
    PROMPT_COMMAND='if [ $? = 0 ]; then PS1a="\e[32;1m"; else PS1a="\e[31;1m"; fi'
    PS1='$(echo -ne $PS1a)[nix \W]\[\e[0m\] '
    alias l='ls --color=auto --group-directories-first -lAhpo'
    ln ${hello_c} hello.c
    ln ${hello_cc} hello.cc

    echo "Verifying that the compiler works: ./test-compiler-sanity.sh"
    ./test-compiler-sanity.sh

    echo "Checking out depot_tools and dawn from git (if needed)"
    [ -d depot_tools ] ||
      git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
    [ -d dawn ] ||
      git clone https://dawn.googlesource.com/dawn.git

    export PATH=$PATH:$PWD/depot_tools
    export DAWN_BUILD_DIR=out/Debug

    cd dawn
    git checkout -d 1fe05467a6da2781ae63b092d336823724a8ae4a
    cp scripts/standalone.gclient .gclient
    echo "running 'gclient sync' in $PWD"
    gclient sync || exit 1

    mkdir -p $DAWN_BUILD_DIR
    cp ${dawn_gn_args} $DAWN_BUILD_DIR/args.gn
    echo "running 'gn gen $DAWN_BUILD_DIR' in $PWD"
    gn gen $DAWN_BUILD_DIR

    echo "running 'ninja' in $PWD/$DAWN_BUILD_DIR"
    ninja -C $DAWN_BUILD_DIR

    #echo "running example app $DAWN_BUILD_DIR/CHelloTriangle"
    #$DAWN_BUILD_DIR/CHelloTriangle
    cd ..

    ./postprocess.sh

    echo "To build the example app:"
    echo "./hello_triangle/build.sh"
  '';
}
