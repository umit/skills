#!/usr/bin/env bash
# Continuously profile a JVM in production with rotating JFR output.
# Designed to run as a systemd service or background daemon.
# Usage: continuous-jfr.sh <pid> [rotate=1h] [dir=./profiles] [event=cpu]

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <pid> [rotate] [dir] [event]

  pid     Java PID.
  rotate  Rotation interval (e.g., 1h, 30m, 24h). Default: 1h.
  dir     Output directory. Default: ./profiles.
  event   Event type. Default: cpu.

Output filenames: <dir>/profile-<event>-<host>-<pid>-<timestamp>.jfr

Stop with: asprof stop <pid>
Or: kill the JVM (in-flight chunk is written on shutdown).
EOF
    exit 1
}

[[ $# -lt 1 ]] && usage

PID="$1"
ROTATE="${2:-1h}"
DIR="${3:-./profiles}"
EVENT="${4:-cpu}"

ASPROF="${ASPROF:-$(command -v asprof || true)}"
if [[ -z "$ASPROF" ]]; then
    echo "Error: asprof not found in PATH." >&2
    exit 1
fi

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Error: PID $PID is not running." >&2
    exit 1
fi

mkdir -p "$DIR"
HOST=$(hostname -s)
PATTERN="$DIR/profile-${EVENT}-${HOST}-${PID}-%t.jfr"

echo "Starting continuous JFR profiling"
echo "  PID:       $PID"
echo "  Event:     $EVENT"
echo "  Rotate:    every $ROTATE"
echo "  Output:    $PATTERN"
echo

"$ASPROF" start \
    -e "$EVENT" \
    -f "$PATTERN" \
    -o jfr \
    "loop=$ROTATE" \
    "$PID"

echo "Started. Stop with:"
echo "  asprof stop $PID"
echo
echo "Tip: prune old profiles with:"
echo "  find $DIR -name 'profile-*.jfr' -mtime +7 -delete"
