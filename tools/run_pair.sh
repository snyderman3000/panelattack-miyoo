#!/bin/sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Run two clients against the local server: A (scripted $1) and B (scripted $2) for $3 seconds
T=${3:-60}
for who in A B; do
  H=/tmp/pa_$who
  if [ ! -f "$H/.data/love/Panel Attack/conf.json" ]; then
    mkdir -p "$H/.data/love/Panel Attack"
    printf '{"name":"P%s%s","language_code":"EN","discordCommunityShown":true,"show_fps":true}' $who $(date +%s | tail -c 5) > "$H/.data/love/Panel Attack/conf.json"
  fi
  rm -rf /tmp/pd_$who; mkdir -p /tmp/pd_$who
done
run() {
  who=$1; script=$2
  HOME=/tmp/pa_$who XDG_DATA_HOME=/tmp/pa_$who/.data PA_HOST_TEST=1 PA_SERVER=127.0.0.1 PA_PROFILE=1 \
  M2D_LIB="$ROOT/mini2d/libmini2d_host.so" M2D_DUMP=/tmp/pd_$who M2D_DUMP_EVERY=${EVERY:-30} M2D_INPUT=$script \
  timeout $T love "${GAME:-$ROOT/game}" > /tmp/pa_$who.log 2>&1
}
run B "$2" &
sleep ${DELAY:-2}
run A "$1"
wait
echo "A frames $(ls /tmp/pd_A | wc -l)  B frames $(ls /tmp/pd_B | wc -l)"
