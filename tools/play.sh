#!/usr/bin/env bash
# Linux counterpart of play.bat: the keyboard is player 1 (merged with any pad,
# key map in play.bat), output goes to play_stdout.txt / play_stderr.txt.
#   tools/play.sh          play
#   tools/play.sh diag     with the frame, GPU and audio diagnostics play.bat diag sets
cd "$(dirname "$0")/.." || exit 1
export RECOMP_KEYBOARD="${RECOMP_KEYBOARD:-1}"
if [ "${1:-}" = diag ]; then
    export RECOMP_FRAME_STATS=1 RECOMP_SLOW_STACKS=50 RECOMP_VKR_STATS=1 \
           RECOMP_GUESTCPU_STATS=1 RECOMP_APU_LEVEL=1 RECOMP_VKR_GPUPROF=25 \
           RECOMP_FPS_OVERLAY=1
fi
exec build-linux/ssx3_recomp > play_stdout.txt 2> play_stderr.txt
