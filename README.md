Builds dawn on Linux as static libraries and runs the CHelloTriangle example

Requirements:
- [nix](https://nixos.org/guides/install-nix.html)

Build:

```sh
nix-shell shell.nix
```

For the demo program to work, your terminal session must have the
appropriate X11 env vars set.
Alternatively you can exit the nix shell after it's done building
and run the CHelloTriangle app in the host env.

To clean the build results (eg to rebuild):

```sh
rm -rf dawn/out
```
