#!/bin/sh
# Every .lean file in the source tree must have a numbered stop in README.md, and every
# stop must link to an existing file. Run from the repository root.
set -eu
tree=$(mktemp)
atlas=$(mktemp)
trap 'rm -f "$tree" "$atlas"' EXIT
find . -name '*.lean' -not -path './.lake/*' | sed 's|^\./||' | sort > "$tree"
grep -E '^### [0-9]+\. \[' README.md | grep -oE '\]\([A-Za-z0-9_/.-]+\.lean\)' |
  sed -E 's/^\]\(//; s/\)$//' | sort > "$atlas"
status=0
missing=$(comm -23 "$tree" "$atlas")
extra=$(comm -13 "$tree" "$atlas")
dups=$(uniq -d "$atlas")
if [ -n "$missing" ]; then echo "Lean files without a README stop:"; echo "$missing"; status=1; fi
if [ -n "$extra" ]; then echo "README stops for files that do not exist:"; echo "$extra"; status=1; fi
if [ -n "$dups" ]; then echo "Files with more than one README stop:"; echo "$dups"; status=1; fi
n=$(wc -l < "$tree" | tr -d ' ')
stops=$(grep -cE '^### [0-9]+\. \[' README.md)
if [ "$stops" -ne "$n" ]; then echo "README has $stops stops for $n Lean files"; status=1; fi
[ "$status" -eq 0 ] && echo "inventory: $n Lean files, $stops README stops, all matched"
exit "$status"
