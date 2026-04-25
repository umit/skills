#!/usr/bin/env bash
# One-shot attach to a running JVM and produce a flame graph.
# Usage: attach.sh <pid> [event=cpu] [seconds=30] [output=./profile-<event>-<pid>-<ts>.html]

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <pid> [event] [seconds] [output]

  pid       Java PID to attach to (find with: jps -v).
  event     Event type: cpu (default), alloc, lock, wall, itimer, cycles, cache-misses.
  seconds   Profiling duration in seconds. Default: 30.
  output    Output file. Default: ./profile-<event>-<pid>-<timestamp>.html.
            Extension determines format: .html|.svg=flamegraph, .jfr=JFR, .txt=collapsed.

Examples:
  $(basename "$0") 12345
  $(basename "$0") 12345 alloc 60
  $(basename "$0") 12345 wall 120 wall.jfr
EOF
    exit 1
}

[[ $# -lt 1 ]] && usage

PID="$1"
EVENT="${2:-cpu}"
SECONDS_DURATION="${3:-30}"
OUTPUT="${4:-profile-${EVENT}-${PID}-$(date +%Y%m%d-%H%M%S).html}"

ASPROF="${ASPROF:-$(command -v asprof || true)}"
if [[ -z "$ASPROF" ]]; then
    echo "Error: asprof not found in PATH. Install with scripts/install.sh." >&2
    exit 1
fi

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Error: PID $PID is not running." >&2
    exit 1
fi

EXTRA_ARGS=()
case "$EVENT" in
    wall) EXTRA_ARGS+=("-t") ;;  # per-thread for wall
    lock) EXTRA_ARGS+=("--lock" "1ms") ;;  # ignore brief contention
esac

echo "Profiling PID=$PID event=$EVENT duration=${SECONDS_DURATION}s"
echo "Output: $OUTPUT"
echo

"$ASPROF" -e "$EVENT" -d "$SECONDS_DURATION" "${EXTRA_ARGS[@]}" -f "$OUTPUT" "$PID"

echo
echo "Done. Open: $OUTPUT"
