Builds dawn on Linux and macOS as one single easier-to-use library.

This is an experiment for [playsys](https://github.com/playbit/playsys)

The goal with this experiment is to make it less complex to build programs using dawn
by allowing simplified linking with a single library. Eventually this will make it
into playsys for the Linux host wgpu implementation.


## Build

Requirements to build: (config.sh checks for all of these)

- Linux with X11 or macOS >=10.15
- cmake >=3.10
- bash or a bash-compatible shell like zsh
- wget or curl
- git
- ninja
- python3

Configure build: (run after every git clone/pull/checkout)

```sh
sh config.sh
```

Build libwgpu:

```sh
bash build.sh
# bash build.sh -clean  # rebuild from scratch
```

Build & run example program:

```sh
bash hello_triangle/build.sh
./hello_triangle/bin/hello_triangle    # statically linked
./hello_triangle/bin/hello_triangle-sh # dynamically linked
```

> Linux note: To run the examples, you must be in an X11 shell
