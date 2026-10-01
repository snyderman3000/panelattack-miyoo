#!/bin/sh
# Panel Attack for Miyoo Mini Plus (OnionOS)
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
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
export PA_PROFILE=1
export PA_VERSION="$(cat "$DIR/VERSION" 2>/dev/null)"
export LD_LIBRARY_PATH="$DIR/lib:/config/lib:/customer/lib:$LD_LIBRARY_PATH"

"$DIR/bin/love" "$DIR/game" >> "$LOG" 2>&1
echo "love exited with code $?" >> "$LOG"
free -m >> "$LOG" 2>&1

[ -n "$OLD_GOV" ] && echo "$OLD_GOV" > $CPU/scaling_governor 2>/dev/null
sync
