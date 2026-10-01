# Building

Everything is cross-compiled on Linux (x86-64) for the Miyoo Mini Plus
(SigmaStar SSD202D, Cortex-A7, glibc 2.28).

## 1. Toolchain and SDK

- **Toolchain:** steward-fu's `mini_toolchain` (gcc 8.2, glibc 2.28), unpacked
  to `/opt/mini` (set `TOOLCHAIN=` to use another path).
- **MI_GFX / MI_SYS headers and libraries:** from
  [steward-fu/sdl2](https://github.com/steward-fu/sdl2), folder `mini/`
  (`mini/inc`, `mini/lib`). Point `MI_SDK=` at that folder.

## 2. LuaJIT

LuaJIT 2.1 (tested with commit `c6ffc141`), built for ARM hard-float and
installed into the toolchain sysroot:

```sh
git clone https://github.com/LuaJIT/LuaJIT && cd LuaJIT
make HOST_CC="gcc -m32" CROSS=/opt/mini/bin/arm-linux-gnueabihf- \
     TARGET_CFLAGS="-mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
make install PREFIX=/usr DESTDIR=/opt/mini/arm-buildroot-linux-gnueabihf/sysroot
```

(`gcc -m32` needs the 32-bit multilib packages on the build machine.)

## 3. LÖVE 11.5

Unmodified LÖVE 11.5 (tag `11.5`). Large-file support is required, otherwise
directory listing fails on the device:

```sh
git clone --branch 11.5 https://github.com/love2d/love && cd love
./platform/unix/automagic
F="-O2 -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -D_FILE_OFFSET_BITS=64 -D_LARGEFILE64_SOURCE"
./configure --host=arm-linux-gnueabihf --prefix=/usr --disable-mpg123 --with-lua=luajit \
  CFLAGS="$F" CXXFLAGS="$F" \
  SDL2_CONFIG=/opt/mini/arm-buildroot-linux-gnueabihf/sysroot/usr/bin/sdl2-config
make -j$(nproc)
```

Set `LOVE_DIR=` to this folder (default `../love`).

## 4. Panel Attack source

```sh
git submodule update --init   # fills upstream/ with the pinned Panel Attack commit
```

Or point `PA_SRC=` at another checkout. `patches.py` checks that every patch
still applies, so moving to a newer Panel Attack fails loudly where the code
changed.

## 5. Package

```sh
LOVE_DIR=../love MI_SDK=../sdl2/mini ./build_pkg.sh          # version from ./VERSION
```

Produces `dist/PanelAttack-miyoo-vX.Y.Z.zip` containing `App/PanelAttack`.
Audio is prepared by `tools/convert_audio.py` (needs `ffmpeg` with libvorbis):
theme sounds are swapped for the CC0 ones in `sounds/` (regenerate them with
`python3 tools/make_sfx.py sounds`), character clips are trimmed and everything
is re-encoded to mono. `NO_AUDIO=1` builds a silent package instead.

## Testing on a PC

`mini2d/build.sh` also builds `libmini2d_host.so`, which renders into memory
and can dump frames. With a desktop LÖVE 11.5 installed:

```sh
./build_game.sh
python3 tools/mkinput.py /tmp/in.txt 200 40 a wait a   # scripted button presses
tools/run_host.sh 20 /tmp/in.txt 30                     # frames land in /tmp/pd as PPM
python3 tools/tile.py /tmp/shot.png 0 10                # combine frames into a PNG
```

`tools/run_pair.sh` runs two clients against a local Panel Attack server
(`luajit serverLauncher.lua` from the Panel Attack repo, with `PA_SERVER=127.0.0.1`).

## Releasing

1. Bump `VERSION`, add `docs/releases/vX.Y.Z.md`, commit to `main`.
2. Build the zip (`./build_pkg.sh`).
3. Add `PanelAttack-miyoo-vX.Y.Z.zip` and the notes (as `notes-vX.Y.Z.md`)
   to the `builds` branch and push it. Its `publish.yml` workflow tags
   `vX.Y.Z` on `main` and publishes the GitHub release with the zip attached.
   Mixtape installs the release asset whose name contains `miyoo`.
