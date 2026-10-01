#!/bin/sh
# Rebuild port/game from the Panel Attack source + Miyoo overlay + patches.
set -e
cd "$(dirname "$0")"
# Panel Attack source: the upstream/ submodule (override with PA_SRC=...)
SRC="${PA_SRC:-upstream}"
[ -f "$SRC/main.lua" ] || { echo "Panel Attack source not found in $SRC (git submodule update --init)"; exit 1; }
rm -rf game
mkdir game
cp -r $SRC/client $SRC/common game/
rm -rf game/client/tests game/common/tests
cp $SRC/main.lua game/pa_main.lua
cp $SRC/COPYING $SRC/COPYING-ASSETS game/ 2>/dev/null || true
cp -r overlay/* game/
python3 patches.py game

# ---- asset trimming for the handheld (memory) ----
A=game/client/assets
rm -rf "$A/default_data/panels/Panel Attack Simple" "$A/default_data/panels/Panel Attack Sharp"
# the full-screen overlay is 95% transparent and costs a full-screen blend per frame
rm -f "$A/themes/Panel Attack Modern/background/bg_overlay"*
rm -f "$A/themes/Panel Attack Modern/background/main"* "$A/themes/Panel Attack Modern/background/title"* "$A/themes/Panel Attack Modern/background/select_screen"* "$A/themes/Panel Attack Modern/background/readme"*
rm -f "$A/default_data/stages/"*/background*
