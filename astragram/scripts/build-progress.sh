#!/bin/bash
# Shows how far a Make.py build is, redrawn in place every few seconds (no scrolling).
#
# usage: astragram/scripts/build-progress.sh <build log> [seconds between updates, default 3]
#
# The log is the build's output (Make.py ... > build.log 2>&1). Bazel finds more actions as it goes, so the total
# grows, and the last big modules (TelegramCore, TelegramUI) take minutes each: the time left is a rough guess.

LOG="$1"
EVERY="${2:-3}"
if [ -z "$LOG" ]; then
    echo "usage: $0 <build log> [seconds]"
    exit 2
fi

while [ ! -f "$LOG" ]; do
    printf '\033[H\033[2J  Waiting for %s ...\n' "$LOG"
    sleep "$EVERY"
done
START=$(stat -f %B "$LOG")

bar() {
    local done=$1 total=$2 width=30 filled
    filled=0
    if [ "$total" -gt 0 ]; then filled=$(( done * width / total )); fi
    printf '['
    printf '%*s' "$filled" '' | tr ' ' '#'
    printf '%*s' $(( width - filled )) '' | tr ' ' '.'
    printf ']'
}

while true; do
    PROGRESS=$(grep -o -E '\[[0-9,]+ / [0-9,]+\]' "$LOG" | tail -1 | tr -d '[],')
    DONE=${PROGRESS%% /*}
    TOTAL=${PROGRESS##*/ }
    [ -n "$DONE" ] || DONE=0
    [ -n "$TOTAL" ] && [ "$TOTAL" != "$PROGRESS" ] || TOTAL=0
    ELAPSED=$(( $(date +%s) - START ))
    # macOS bash 3.2 evaluates both sides of ?: in $(( )), so zero is checked with if.
    LEFT=0
    if [ "$DONE" -gt 0 ]; then LEFT=$(( ELAPSED * (TOTAL - DONE) / DONE )); fi
    PERCENT=0
    if [ "$TOTAL" -gt 0 ]; then PERCENT=$(( 100 * DONE / TOTAL )); fi
    NOW=$(grep -o -E '\] [A-Z][a-z]+ [^;]*' "$LOG" | tail -1 | cut -c3- | cut -c1-70)
    ERRORS=$(grep -c -E ': error:' "$LOG")

    printf '\033[H\033[2J'
    printf '  AstraGram build\n\n'
    printf '  %s %3d%%\n' "$(bar "$DONE" "$TOTAL")" "$PERCENT"
    printf '  Actions:  %s of %s\n' "$DONE" "$TOTAL"
    printf '  Elapsed:  %d min %02d s\n' $(( ELAPSED / 60 )) $(( ELAPSED % 60 ))
    printf '  Left:     ~%d min (rough)\n' $(( LEFT / 60 ))
    printf '  Errors:   %s\n' "$ERRORS"
    printf '  Now:      %s\n' "$NOW"

    if grep -q -E 'Build completed successfully' "$LOG"; then
        printf '\n  DONE: the build completed.\n'
        break
    fi
    if grep -q -E 'Build did NOT complete|Traceback' "$LOG"; then
        printf '\n  FAILED: see the log:\n  %s\n' "$LOG"
        break
    fi
    sleep "$EVERY"
done
