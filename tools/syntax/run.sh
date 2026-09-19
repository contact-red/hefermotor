#!/usr/bin/env bash
# The corpus run: the parser over every file of the packages beside the
# ponyc on PATH and every single-edit mutant of each, a sample of those
# mutants against ponyc's verdict, every module's items and types
# against ponyc's AST, and the numbers the design records.
#
# Usage: tools/syntax/run.sh <syntax binary> <hefermotor binary>
#
# Five steps, each failing the run on its own.
#
# 1. `syntax --check` over the packages directory, and with PONYC_SRC
#    set, over that checkout's `examples/`, `test/full-program-tests/`
#    and `tools/`: every tree must keep the invariants, and the summary
#    line must count every `.pony` file under those directories, since
#    a run whose actors never all report exits 0 without one. The run
#    is on one scheduler thread, so that the lines parsed over its user
#    and system CPU seconds, printed as lines/s/core, is one core's
#    rate and not that of several threads contending.
# 2. `syntax --mutants --emit` over the packages directory, every
#    CORPUS_EVERY-th mutant (default 101, prime to the 48 mutants of a
#    file so the sample cycles through every edit), then
#    `tools/differential/run.sh` over the sample: every mutant's verdict
#    must agree with `ponyc --pass=parse`, and at least one mutant must
#    be rejected, since a sample no edit reached agrees trivially; the
#    two position rates are on its summary line.
# 3. `agree.py` over every package under the packages directory, and
#    with PONYC_SRC set over every package under the checkout's
#    `test/full-program-tests/`: every module's items and types must
#    match ponyc's parse-pass AST, or be listed under
#    `tools/syntax/known_gaps/` with exactly its diff; and every gap
#    file must be named in `docs/ponyc-divergences.md`.
# 4. The token digests of the packages, regenerated and compared with
#    `tools/syntax/token_digest/`; a difference means the lexer's kinds
#    over the stdlib changed, or the stdlib did.
# 5. `hefermotor check stdlib` from an empty directory, timed.
#
# Each step's tool invocations run under DIFFERENTIAL_TIMEOUT seconds
# (default 600): the digest step as a whole, the others per invocation.
set -u

syntax=${1:?usage: $0 <syntax binary> <hefermotor binary>}
hefermotor=${2:?usage: $0 <syntax binary> <hefermotor binary>}
syntax=$(cd "$(dirname "$syntax")" && pwd)/$(basename "$syntax")
hefermotor=$(cd "$(dirname "$hefermotor")" && pwd)/$(basename "$hefermotor")
here=$(cd "$(dirname "$0")" && pwd)
timeout_s=${DIFFERENTIAL_TIMEOUT:-600}
every=${CORPUS_EVERY:-101}

ponyc_bin=$(command -v ponyc) || { echo "no ponyc on PATH" >&2; exit 2; }
packages=$(cd "$(dirname "$(readlink -f "$ponyc_bin")")/../packages" && pwd) \
  || { echo "no packages directory beside ponyc" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

# --- 1. every file and every mutant keeps the invariants --------------

trees=("$packages")
if [ -n "${PONYC_SRC:-}" ]; then
  for d in examples test/full-program-tests tools; do
    [ -d "$PONYC_SRC/$d" ] || { echo "no $PONYC_SRC/$d" >&2; exit 2; }
    trees+=("$PONYC_SRC/$d")
  done
fi
{ TIMEFORMAT='%R %U %S'; time timeout "$timeout_s" "$syntax" --check \
  "${trees[@]}" --ponymaxthreads 1 > "$tmp/check.txt" 2> "$tmp/check.err"; } \
  2> "$tmp/check.time"
code=$?
cat "$tmp/check.txt"
files=$(find "${trees[@]}" -name '*.pony' | wc -l)
counted=$(sed -n 's/^check: \([0-9]*\) files, .*$/\1/p' "$tmp/check.txt")
lines=$(sed -n 's/^check: .* \([0-9]*\) lines parsed$/\1/p' "$tmp/check.txt")
if [ "$code" != 0 ]; then
  cat "$tmp/check.err" >&2
  fail "syntax --check exited $code"
elif [ "$counted" != "$files" ]; then
  fail "syntax --check counted '$counted' files, find counts $files"
else
  read -r real user sys < "$tmp/check.time"
  echo "check: $lines lines in ${real}s real, ${user}s user, ${sys}s sys:" \
    "$(awk -v l="$lines" -v u="$user" -v s="$sys" \
      'BEGIN { printf "%.0f", l / (u + s) }') lines/s/core"
fi

# --- 2. a sample of the mutants against ponyc's verdict ---------------

if timeout "$timeout_s" "$syntax" --mutants "$packages" \
  --emit "$tmp/sample" --every "$every"
then
  "$here/../differential/run.sh" "$hefermotor" "$tmp"/sample/* \
    | tee "$tmp/sample.txt"
  code=${PIPESTATUS[0]}
  rejected=$(sed -n \
    's/^differential: .* sample positions [0-9]* of \([0-9]*\),.*$/\1/p' \
    "$tmp/sample.txt")
  if [ "$code" = 1 ]; then
    fail "the sample differs from ponyc"
  elif [ "$code" != 0 ]; then
    fail "the harness could not score the sample (exit $code)"
  elif [ "${rejected:-0}" = 0 ]; then
    fail "no sampled mutant was rejected"
  fi
else
  fail "syntax --mutants exited $?"
fi

# --- 3. the items and types against ponyc's AST -------------------------

oracle_dirs=("$packages")
if [ -n "${PONYC_SRC:-}" ]; then
  oracle_dirs+=("$PONYC_SRC/test/full-program-tests")
fi
mapfile -t oracle_packages < <(find "${oracle_dirs[@]}" -name '*.pony' \
  -exec dirname {} \; | LC_ALL=C sort -u)
roots=()
for d in "${oracle_dirs[@]}"; do roots+=(--root "$d"); done
timeout "$timeout_s" "$here/agree.py" --known-gaps "$here/known_gaps" \
  "${roots[@]}" "$syntax" "${oracle_packages[@]}"
code=$?
if [ "$code" = 1 ]; then
  fail "the items and types differ from ponyc's AST"
elif [ "$code" != 0 ]; then
  fail "agree.py could not compare (exit $code)"
fi
for gap in "$here"/known_gaps/*.diff; do
  [ -e "$gap" ] || continue
  if ! grep -q -F "$(basename "$gap")" "$here/../../docs/ponyc-divergences.md"
  then
    fail "$(basename "$gap") has no entry in docs/ponyc-divergences.md"
  fi
done

# --- 4. the token digests -----------------------------------------------

timeout "$timeout_s" "$here/token_digest.sh" "$syntax" "$packages" \
  "$tmp/digest"
code=$?
if [ "$code" != 0 ]; then
  fail "token_digest.sh exited $code"
elif diff -r "$here/token_digest" "$tmp/digest"; then
  echo "token digests: $(find "$tmp/digest" -type f | wc -l)" \
    "packages unchanged"
else
  fail "token digests differ from tools/syntax/token_digest"
fi

# --- 5. the command over the stdlib, timed ------------------------------

mkdir -p "$tmp/cwd"
{ TIMEFORMAT='%R %U %S'; time (cd "$tmp/cwd" && \
  timeout "$timeout_s" "$hefermotor" check stdlib > "$tmp/stdlib.out" \
  2> "$tmp/stdlib.err"); } 2> "$tmp/stdlib.time"
code=$?
read -r real user sys < "$tmp/stdlib.time"
if [ "$code" != 0 ]; then
  cat "$tmp/stdlib.err" >&2
  fail "hefermotor check stdlib exited $code"
else
  echo "hefermotor check stdlib: ${real}s real, ${user}s user, ${sys}s sys"
fi

if [ "$failures" != 0 ]; then
  echo "corpus: $failures failure(s)"
  exit 1
fi
echo "corpus: ok"
