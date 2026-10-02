#!/bin/sh
# Assemble Roms/PORTS/Games/PanelAttack (OnionOS Ports) for the SD card and zip it.
set -e
cd "$(dirname "$0")"
VERSION="${1:-$(cat VERSION)}"
# cross-built LÖVE 11.5 tree (see docs/BUILDING.md)
LOVE_DIR="${LOVE_DIR:-../love}"
TOOLCHAIN="${TOOLCHAIN:-/opt/mini}"
./build_game.sh
./mini2d/build.sh
./dspfix/build.sh
OUT=pkg/Roms/PORTS/Games/PanelAttack
rm -rf pkg && mkdir -p $OUT/bin $OUT/lib
ST=$TOOLCHAIN/bin/arm-linux-gnueabihf-strip
cp "$LOVE_DIR/src/.libs/love" $OUT/bin/love
cp "$LOVE_DIR/src/.libs/liblove-11.5.so" $OUT/lib/
$ST $OUT/bin/love $OUT/lib/liblove-11.5.so
S=$TOOLCHAIN/arm-buildroot-linux-gnueabihf/sysroot/usr/lib
for n in libatomic.so.1 libbz2.so.1.0 libfreetype.so.6 libgcc_s.so.1 libjson-c.so.5 libluajit-5.1.so.2 libmodplug.so.1 libogg.so.0 libopenal.so.1 libpng16.so.16 libstdc++.so.6 libtheoradec.so.1 libvorbis.so.0 libvorbisfile.so.3 libz.so.1; do
  cp -L $S/$n $OUT/lib/$n
done
$ST $OUT/lib/*.so* 2>/dev/null || true
cp mini2d/libmini2d.so dspfix/libdspfix.so $OUT/lib/
# SDL2 is only used for events/threads/timers (no video), so the plain SDL2
# from the Miyoo sysroot is enough
cp -L $S/libSDL2-2.0.so.0 $OUT/lib/
cp -r game $OUT/game
rm -f $OUT/game/pa_conf.lua
# Windows/mac libraries are useless here
find $OUT/game \( -name "*.dll" -o -name "*.dylib" \) -delete
# silent build: keep the audio file names (the game checks they exist) but drop the data
# sound: replace theme sounds we may not redistribute, trim and re-encode the
# rest (tools/convert_audio.py). NO_AUDIO=1 makes a silent build instead.
if [ -n "$NO_AUDIO" ]; then
  find $OUT/game \( -name "*.ogg" -o -name "*.mp3" -o -name "*.wav" -o -name "*.flac" \) -exec truncate -s 0 {} +
else
  python3 tools/convert_audio.py $OUT/game sounds
fi
cp pkgsrc/alsoft.conf $OUT/ 2>/dev/null || true
cp pkgsrc/* $OUT/
sed -i 's#:$DIR/libsdl##' $OUT/launch.sh
echo "$VERSION" > $OUT/VERSION
mkdir -p $OUT/licenses
cp LICENSE $OUT/licenses/LICENSE-port.txt
cp THIRD_PARTY_NOTICES.md $OUT/licenses/
chmod +x $OUT/launch.sh $OUT/bin/love
ZIP="PanelAttack-miyoo-v$VERSION.zip"
mkdir -p dist
# Ports list entry + box art
mkdir -p "pkg/Roms/PORTS/Shortcuts/Puzzle games" pkg/Roms/PORTS/Imgs
# both names: OnionOS's "Import ports" prefers the .notfound copy and turns it into .port
cp pkgsrc/PanelAttack.port "pkg/Roms/PORTS/Shortcuts/Puzzle games/Panel Attack.port"
cp pkgsrc/PanelAttack.port "pkg/Roms/PORTS/Shortcuts/Puzzle games/Panel Attack.notfound"
python3 -c "from PIL import Image; Image.open('docs/cover.png').convert('RGB').resize((320, 240), Image.LANCZOS).save('pkg/Roms/PORTS/Imgs/Panel Attack.png')"
rm -f $OUT/PanelAttack.port
(cd pkg && rm -f "../dist/$ZIP" && zip -qr9 "../dist/$ZIP" Roms)
du -sh $OUT; ls -la "dist/$ZIP"
