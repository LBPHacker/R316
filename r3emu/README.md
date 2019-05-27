# r3emu

An emulator for an architecture that doesn't even exist yet. In fact, it'll
help a lot with figuring out what to put into that architecture.

## Building

### Release

```sh
meson build && cd build
meson configure -Dwerror=true -Dwarning_level=3 -Dcpp_std=c++17 -Db_lto=true -Dbuildtype=release -Dstrip=true
ninja
```

### Debug

```sh
meson build && cd build
meson configure -Dwerror=true -Dwarning_level=3 -Dcpp_std=c++17
ninja
```

## Running

Currently the emulator is pretty useless without the helpers in `autorun.lua`.

```sh
./r3emu ../autorun.lua # assuming pwd is ./build
```
