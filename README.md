Builds dawn on Linux as static libraries and runs the CHelloTriangle example


## Build

Requires [nix](https://nixos.org/guides/install-nix.html)

```sh
nix-shell --pure shell.nix
# build example app
./hello_triangle/build.sh

# exit nix shell and try the demo program:
# (this may or may not work; dynamically linked)
./dawn/out/Debug/CHelloTriangle
```

To clean the build results (eg to rebuild):

```sh
rm -rf dawn/out
```


## Known issues


### `hello_triangle/build.sh` fails

This is expected as linking dawn is a work in progress


### `Assertion failure at dawn_native/vulkan/NativeSwapChainImplVk.cpp`

When resizing the window of one of the example apps, the vulkan swapchain
seem to fail. This appears to be a bug in Dawn.


### X11 and a other shared libs needed for the example apps

For the demo program to work, your terminal session must have the
appropriate X11 env vars set.
Alternatively you can exit the nix shell after it's done building
and run the CHelloTriangle app in the host env.

