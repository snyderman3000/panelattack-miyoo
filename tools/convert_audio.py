#!/usr/bin/env python3
"""Prepares Panel Attack's sounds for the Miyoo Mini Plus (run on the packaged
game folder by build_pkg.sh).

- Theme sound effects from the Unity Asset Store (licensed to official Panel
  Attack releases only) and the unlicensed default chain sound are replaced
  with the CC0 sounds in sounds/ (made by tools/make_sfx.py).
- Character sound effects keep at most three variants of each sound and one
  per chain/combo size: static sounds are decoded into RAM, and the full set
  would need up to ~30 MB per character.
- Everything is re-encoded to mono (the handheld has one speaker): music at
  32 kHz, sound effects at 22.05 kHz. That roughly halves decoding work.

usage: tools/convert_audio.py GAME_DIR SOUNDS_DIR
"""
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

REPLACED_THEME_SFX = re.compile(r"^(countdown|fanfare\d*|gameover|go|land|menu_cancel|menu_move|menu_validate|move|notification|swap|thud_\d+)\.ogg$")
VARIANT_GROUPS = re.compile(r"^(win|lose|selection|taunt_up|taunt_down|garbage_land|garbage_match)(\d*)\.ogg$")
SIZED_VARIANT = re.compile(r"^(chain|combo)\d+_\d+\.ogg$")
MAX_VARIANTS = 3


def is_music(path):
    name = os.path.basename(path)
    return "music" in name or "/music/" in path


def main():
    game, sounds = sys.argv[1], sys.argv[2]
    assets = os.path.join(game, "client", "assets")
    theme_sfx = os.path.join(assets, "themes", "Panel Attack Modern", "sfx")

    # 1) replacements
    replaced = 0
    for f in os.listdir(theme_sfx):
        if REPLACED_THEME_SFX.match(f):
            os.remove(os.path.join(theme_sfx, f))
            replaced += 1
    for f in os.listdir(sounds):
        if f.endswith(".ogg") and f != "chain.ogg":
            shutil.copy(os.path.join(sounds, f), os.path.join(theme_sfx, f))
    default_chain = os.path.join(assets, "characters", "__default", "chain.ogg")
    if os.path.exists(default_chain):
        shutil.copy(os.path.join(sounds, "chain.ogg"), default_chain)

    # 2) trim character sound variants
    dropped = 0
    chars = os.path.join(assets, "default_data", "characters")
    for c in os.listdir(chars):
        d = os.path.join(chars, c)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            m = VARIANT_GROUPS.match(f)
            if SIZED_VARIANT.match(f) or (m and m.group(2) and int(m.group(2)) > MAX_VARIANTS):
                os.remove(os.path.join(d, f))
                dropped += 1

    # 3) re-encode
    jobs = []
    for root, _, files in os.walk(assets):
        for f in files:
            p = os.path.join(root, f)
            if f.endswith(".ogg") and os.path.getsize(p) > 0 and not p.startswith(os.path.join(sounds, "")):
                jobs.append(p)

    def encode(p):
        music = is_music(p)
        tmp = p + ".tmp.ogg"
        args = ["ffmpeg", "-v", "error", "-y", "-i", p, "-map_metadata", "-1", "-ac", "1",
                "-ar", "32000" if music else "22050", "-c:a", "libvorbis", "-q:a", "2" if music else "3", tmp]
        subprocess.run(args, check=True)
        os.replace(tmp, p)

    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        list(ex.map(encode, jobs))
    print("audio: %d theme sounds replaced, %d character variants dropped, %d files re-encoded" % (replaced, dropped, len(jobs)))


if __name__ == "__main__":
    main()
