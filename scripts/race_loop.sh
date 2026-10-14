#!/usr/bin/env bash
# Boot -> race load, N times, headless (Start pulses drive the menus into the
# first event). Classifies each run and keeps its log in logs/loop/.
#
#   scripts/race_loop.sh [runs] [-- extra VAR=value ...]
#
# OK    reached [STATE] ingame
# CRASH [CRASH] in the log
# STALL still loading after STALL_SECS with no state change
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS=${1:-5}; shift || true
[ "${1:-}" = "--" ] && shift
STALL_SECS=${STALL_SECS:-120}
OUT="$HERE/logs/loop"; mkdir -p "$OUT"
cd "$HERE"
for i in $(seq 1 "$RUNS"); do
    ts=$(date +%Y%m%d-%H%M%S); log="$OUT/$ts.txt"
    env SDL_VIDEODRIVER=dummy RECOMP_PAD_PRESS=0x10 RECOMP_STREAM_CHECK=1 "$@" \
        build-linux/ssx3_recomp > "$log" 2>&1 &
    pid=$!
    res=""; last_change=$SECONDS; last=""
    while kill -0 $pid 2>/dev/null; do
        sleep 2
        st=$(grep -a "^\[STATE\]" "$log" | tail -1 | awk '{print $3}')
        [ "$st" != "$last" ] && { last="$st"; last_change=$SECONDS; }
        if grep -aq 00299D7C <<<"$st"; then res=OK; break; fi
        if grep -aq "^\[CRASH\]" "$log"; then res=CRASH; break; fi
        if [ $((SECONDS - last_change)) -gt "$STALL_SECS" ]; then res=STALL; break; fi
    done
    [ -z "$res" ] && res=EXIT
    if [ "$res" = STALL ]; then
        # Thread + streamer dump into the log, then EA's file table via gdb.
        kill -USR1 $pid; sleep 20
        gdb -p $pid -batch -x "$HERE/scripts/ea_filetable.gdb" -ex detach 2>&1 \
            | grep -E "^table|^fd" > "$OUT/$ts.filetable.txt"
    fi
    if [ "$res" = STALL ] && [ -n "${HOLD:-}" ]; then
        echo "run $i: STALL, game left running as pid $pid  $log"; exit 0
    fi
    kill -9 $pid 2>/dev/null; wait $pid 2>/dev/null
    # Load time: [STATE] timestamps of loading -> ingame (ms in the log).
    lt=$(awk '/vt=0029B0DC/ && !a {sub("t=","",$2); a=$2} /vt=00299D7C/ && a && !b {sub("t=","",$2); b=$2} END{if (a && b) printf "load %.1fs", (b-a)/1000}' "$log")
    echo "run $i: $res  $lt  $log"
    gzip -f "$log"
done
