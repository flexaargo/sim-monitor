#!/bin/bash
# Regenerates the README images in docs/images from sample data.
# Needs Screen Recording permission for the terminal you run it from.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product SimMonitor
BIN="$(swift build --show-bin-path)/SimMonitor"
LOG="$(mktemp)"

shot() {
    local out="docs/images/$1"; shift
    : > "$LOG"
    env SIMMONITOR_DEBUG_WINDOW=1 SIMMONITOR_DEMO=1 "$@" "$BIN" > "$LOG" 2>&1 &
    local pid=$!
    for _ in $(seq 1 40); do grep -q FRAME "$LOG" && break; sleep 0.5; done
    local region
    region="$(grep FRAME "$LOG" | head -1 | cut -d' ' -f2)"
    screencapture -x -R "$region" "$out"
    kill "$pid"
    wait "$pid" 2>/dev/null || true
    echo "Wrote $out"
}

shot overview.png SIMMONITOR_KEYS=dd
shot details.png SIMMONITOR_EXPAND=0 SIMMONITOR_KEYS=d
shot multi-select.png SIMMONITOR_SELECT=2 SIMMONITOR_KEYS=dddSS
