#!/bin/sh
# Panel Attack for Miyoo Mini Plus (OnionOS)
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# Versions before 0.9.0 lived in Apps: bring the old settings over, then remove it
OLD=/mnt/SDCARD/App/PanelAttack
if [ -d "$OLD" ] && [ "$OLD" != "$DIR" ]; then
  if [ -d "$OLD/data" ] && [ ! -d "$DIR/data" ]; then mv "$OLD/data" "$DIR/data"; fi
  rm -rf "$OLD"
fi
LOG="$DIR/log.txt"
CPU=/sys/devices/system/cpu/cpu0/cpufreq

# keep the last run's log for comparison
[ -f "$LOG" ] && mv "$LOG" "$DIR/log.prev.txt"
{
  echo "===== Panel Attack $(cat "$DIR/VERSION" 2>/dev/null) $(date)"
  free -m
} > "$LOG" 2>&1

OLD_GOV="$(cat $CPU/scaling_governor 2>/dev/null)"
echo performance > $CPU/scaling_governor 2>/dev/null

mkdir -p "$DIR/data"
export HOME="$DIR/data"
export XDG_DATA_HOME="$DIR/data"
export M2D_LIB="$DIR/lib/libmini2d.so"
# Troubleshooting: PA_PROFILE=1 logs frame times, PA_DEBUG=1 logs everything
# export PA_PROFILE=1
# export PA_DEBUG=1
export PA_VERSION="$(cat "$DIR/VERSION" 2>/dev/null)"
# Sound: OnionOS plays OSS (/dev/dsp) audio through its audioserver when
# libpadsp.so is preloaded; OpenAL Soft is pointed at that.
# (OnionOS's own copy first, so add-ons that hook it, like MiniAmp's music in games, apply here too)
for p in /mnt/SDCARD/miyoo/lib/libpadsp.so /customer/lib/libpadsp.so /mnt/SDCARD/.tmp_update/lib/libpadsp.so; do
  # libdspfix forwards open64("/dev/dsp") (used by OpenAL) to libpadsp's open()
  if [ -f "$p" ]; then export LD_PRELOAD="$DIR/lib/libdspfix.so $p"; break; fi
done
echo "audio: LD_PRELOAD=${LD_PRELOAD:-none} audioserver=$(ps | grep -c [a]udioserver)" >> "$LOG"
export ALSOFT_CONF="$DIR/alsoft.conf"
export ALSOFT_LOGLEVEL=1   # OpenAL errors only
export LD_LIBRARY_PATH="$DIR/lib:/config/lib:/customer/lib:$LD_LIBRARY_PATH"

"$DIR/bin/love" "$DIR/game" >> "$LOG" 2>&1
echo "love exited with code $?" >> "$LOG"
free -m >> "$LOG" 2>&1

[ -n "$OLD_GOV" ] && echo "$OLD_GOV" > $CPU/scaling_governor 2>/dev/null
sync
