#!/bin/sh
# Run every Forth example on a real board: scripts/hil/run-all.sh <board> <serial-device>
# Prints one PASS/FAIL line per program; exits non-zero if any fails.
set -u
board=$1; tty=$2
fail=0
for f in examples/forth/*.fs; do
  if out=$(scripts/hil/run-board.sh "$board" "$f" "$tty" 2>&1); then
    echo "$out" | head -1
  else
    echo "FAIL  $(basename "$f" .fs) on $board"; echo "$out" | sed 's/^/    /'; fail=1
  fi
done
exit $fail
