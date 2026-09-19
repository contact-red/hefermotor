#!/usr/bin/env bash
# The known-gaps protocol of agree.py, exercised over the shape fixture
# with a stored ponyc output edited by one atom: the edit is a DIFFER
# with exit 1; the diff agree.py printed, saved as the module's gap
# file, makes it a known gap with exit 0; the unedited output beside
# that gap file is a closed gap with exit 1; and a gap file naming no
# module is stale with exit 1.
#
# Usage: tools/syntax/agree_check.sh <syntax binary>
set -eu

syntax=${1:?usage: $0 <syntax binary>}
here=$(cd "$(dirname "$0")" && pwd)
fixture=$here/fixtures/shape

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/gaps"

# expect <exit code> <summary pattern> <label> <agree.py args...>
expect() {
  local code=$1 pattern=$2 label=$3
  shift 3
  local got=0
  "$here/agree.py" "$@" > "$tmp/out.txt" || got=$?
  if [ "$got" != "$code" ] || ! grep -q -- "$pattern" "$tmp/out.txt"; then
    echo "agree_check: $label: exit $got, expected $code with '$pattern':"
    cat "$tmp/out.txt"
    exit 1
  fi
}

sed 's/(id Foo)/(id Bar)/' "$fixture/expected.ast" > "$tmp/edited.ast"
expect 1 "differ 1" "an edited output differs" \
  --expected "$tmp/edited.ast" --known-gaps "$tmp/gaps" "$syntax" "$fixture"
sed -n '/^--- ponyc/,$p' "$tmp/out.txt" | sed '$d' \
  > "$tmp/gaps/shape__items.pony.diff"
expect 0 "known 1" "the printed diff is the gap" \
  --expected "$tmp/edited.ast" --known-gaps "$tmp/gaps" "$syntax" "$fixture"
expect 1 "closed 1" "an agreeing module with a gap file is closed" \
  --expected "$fixture/expected.ast" --known-gaps "$tmp/gaps" "$syntax" \
  "$fixture"
mv "$tmp/gaps/shape__items.pony.diff" "$tmp/gaps/shape__gone.pony.diff"
expect 1 "stale gap file" "a gap file naming no module is stale" \
  --expected "$fixture/expected.ast" --known-gaps "$tmp/gaps" "$syntax" \
  "$fixture"
echo "agree_check: the known-gaps protocol holds"
