#!/bin/sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# usage: run_host.sh <seconds> [input-script] [dump-every] [keep-home]
T=${1:-30}
[ -z "$4" ] && rm -rf /tmp/pahome
rm -rf /tmp/pd; mkdir -p /tmp/pahome /tmp/pd
export HOME=/tmp/pahome XDG_DATA_HOME=/tmp/pahome/.data PA_HOST_TEST=1
export M2D_LIB="$ROOT/mini2d/libmini2d_host.so" M2D_DUMP=/tmp/pd M2D_DUMP_EVERY=${3:-60}
[ -n "$2" ] && export M2D_INPUT="$2"
timeout $T love "$ROOT/game" > /tmp/pa.log 2>&1
echo "rc=$? frames=$(ls /tmp/pd | wc -l)"
grep -n "Error\|error\|WARN" /tmp/pa.log | head -20
