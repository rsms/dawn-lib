Builds dawn on Linux as one library

This is an experiment for [playsys](https://github.com/playbit/playsys)

The goal with this experiment is to make it less complex to build programs using dawn
by allowing simplified linking with a single library. Eventually this will make it
into playsys for the Linux host wgpu implementation.


## Build

Requirements to build: (setup.sh checks for all of these)

- [clang >=12](https://github.com/llvm/llvm-project/releases/tag/llvmorg-13.0.0)
- bash
- cmake >=3.10
- wget
- git
- ninja
- python3
- sha256sum
- tar

First time setup: (or after `git pull`)

```sh
./setup.sh
```

Build libwgpu:

```sh
./build.sh
# ./build.sh -clean  # rebuild from scratch
```

Build & run example program: (must be in X11 shell to run)

```sh
./hello_triangle/build.sh
./hello_triangle/bin/hello_triangle
```

