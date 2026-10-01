# Third-party notices

The port code in this repository (build scripts, `patches.py`, `overlay/`,
`mini2d/`, `pkgsrc/`, `tools/`) is MIT licensed, see `LICENSE`.
The release zip also contains the following software and assets, each under
its own license.

| Component | License | Source |
|---|---|---|
| Panel Attack (game code) | zlib; bundled libraries listed in its `COPYING` | https://github.com/panel-attack/panel-game |
| Panel Attack (art, music, characters) | various, per file; see `COPYING-ASSETS` in the game folder | same |
| LÖVE 11.5 | zlib | https://github.com/love2d/love |
| LuaJIT 2.1 | MIT | https://github.com/LuaJIT/LuaJIT |
| SDL2 (from the Miyoo Mini toolchain) | zlib | https://github.com/steward-fu/sdl2 |
| OpenAL Soft 1.21.1 | LGPL-2.1-or-later, dynamically linked | https://github.com/kcat/openal-soft (source attached to every release as `openal-soft-1.21.1-source.tar.gz`) |
| FreeType | FreeType License (FTL) | https://freetype.org |
| libpng, zlib | libpng / zlib licenses | http://www.libpng.org, https://zlib.net |
| libogg, libvorbis, libtheora | BSD-3-Clause | https://xiph.org |
| libmodplug | public domain | https://github.com/Konstanty/libmodplug |
| bzip2 | bzip2 license (BSD-style) | https://sourceware.org/bzip2 |
| json-c | MIT | https://github.com/json-c/json-c |
| GCC runtime (libgcc_s, libstdc++, libatomic) | GPL-3.0 with the GCC Runtime Library Exception | https://gcc.gnu.org |
| Rubik font | SIL Open Font License 1.1 (`game/miyoo/fonts/OFL-Rubik.txt`) | https://github.com/googlefonts/rubik |
| Chakra Petch font | SIL Open Font License 1.1 (`game/miyoo/fonts/OFL-ChakraPetch.txt`) | https://github.com/cadsondemak/Chakra-Petch |

The shared libraries above come unmodified from the Miyoo Mini toolchain
sysroot (steward-fu's `mini_toolchain`). OpenAL Soft is loaded as a separate
shared library (`lib/libopenal.so.1`), so it can be replaced with any
compatible build. Its complete source code is attached to each GitHub release
of this port.
