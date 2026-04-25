#!/usr/bin/env bash
# Generate a differential flame graph between two JFR recordings.
# Red = regressed (more samples), Blue = improved (fewer samples).
# Usage: diff-profiles.sh <baseline.jfr> <current.jfr> [output=diff.html] [event=cpu]

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <baseline.jfr> <current.jfr> [output] [event]

  baseline.jfr   JFR before the change.
  current.jfr    JFR after the change.
  output         Output HTML file. Default: diff-<timestamp>.html.
  event          Event type to compare: cpu (default), alloc, lock, wall.

Notes:
  - Both recordings should be captured under the same workload (same RPS, same input).
  - Run baseline and current at the same duration.
  - Red frames in changed code = regression. Blue = improvement.

Example:
  $(basename "$0") before.jfr after.jfr cpu-diff.html
  $(basename "$0") before.jfr after.jfr alloc-diff.html alloc
EOF
    exit 1
}

[[ $# -lt 2 ]] && usage

BASELINE="$1"
CURRENT="$2"
OUTPUT="${3:-diff-$(date +%Y%m%d-%H%M%S).html}"
EVENT="${4:-cpu}"

JFRCONV="${JFRCONV:-$(command -v jfrconv || true)}"
if [[ -z "$JFRCONV" ]]; then
    echo "Error: jfrconv not found in PATH (ships with async-profiler)." >&2
    exit 1
fi

[[ -f "$BASELINE" ]] || { echo "Error: baseline not found: $BASELINE" >&2; exit 1; }
[[ -f "$CURRENT"  ]] || { echo "Error: current not found:  $CURRENT"  >&2; exit 1; }

echo "Diffing"
echo "  Baseline: $BASELINE"
echo "  Current:  $CURRENT"
echo "  Event:    $EVENT"
echo "  Output:   $OUTPUT"
echo

"$JFRCONV" "--$EVENT" --diff "$BASELINE" "$CURRENT" "$OUTPUT"

echo
echo "Done. Open: $OUTPUT"
echo "  Red = regression (more samples)"
echo "  Blue = improvement (fewer samples)"
