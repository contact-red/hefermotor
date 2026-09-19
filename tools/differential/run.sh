#!/usr/bin/env bash
# Differential harness: hefermotor against the ponyc on PATH.
#
# Usage: tools/differential/run.sh <hefermotor binary> [case dir ...]
#
# A fixture case is a directory holding a `main/` package; a stdlib case
# is a directory holding a `.pony` file under the packages directory
# beside ponyc. With no case given, every directory under
# tools/differential/cases and every stdlib case runs. Both tools
# resolve the target and `builtin` against the working directory, so
# each case runs both with the same working directory and an absolute
# target: the fixture's directory, or an empty directory for a stdlib
# case. Neither tool gets a search path option, so both search the same
# roots. Each tool invocation is limited to DIFFERENTIAL_TIMEOUT seconds
# (default 600); a timeout is a crash.
#
# Scoring. The verdict is `ponyc -V2 --pass=scope <dir>`, or
# `--pass=parse` for a fixture whose name starts `syntax-`: exit 0 is
# accept, 255 is reject, anything else is a crash; hefermotor's `--json`
# exit 0 is accept, 1 is reject, 2 aborts the run, anything else is a
# crash, and a document not shaped as one format-1 line (`format` and
# `export_digest` first, `diagnostics` last) is a crash. On a case both
# accept, the package set from ponyc's `Building <locator> -> <path>`
# lines is compared with the document's `packages[].dir`, and the group
# partition from `ponyc -V3 --pass=reach <dir>` is compared as sets of
# basename sets with the document's `groups`. The partition is not
# compared when two packages share a basename or when ponyc printed no
# dump; the summary counts such cases, and a dump call that times out
# is a crash. A `syntax-` fixture is scored on the verdict, never on
# packages or groups, and when both reject, on positions: every
# `<path>:<line>:<col>:` at the start of a line of ponyc's stderr (its
# `Info:` frames are indented) must be the position of a `parse/`
# diagnostic in hefermotor's document (`positions.py`), the class
# `positions`; the check runs one way, since ponyc resumes only at the
# next `use` or entity keyword and hefermotor at the member and the
# statement too. The number of distinct hefermotor positions must equal
# the integer in the case's `EXPECT` file, the class `count`; and
# whether hefermotor's lowest position is ponyc's is summed into
# `first-position agree A of B` on the summary line. A case directory
# holding a file named KNOWN_GAP is expected to differ in exactly the
# classes the file lists, one per line, from `verdict`, `packages`,
# `groups`, `positions` and `count`: that difference is reported as
# `known gap` and does not fail the run, a different set of classes is
# a DIFFER, and an agreement is reported as `known gap closed` and
# counted so the marker's removal is noticed. A `syntax-` fixture both
# tools accept is a `count` difference unless its EXPECT is 0, so a
# fixture meant to be broken cannot pass by being valid.
#
# The sentinel case, `cases/sentinel`, runs first: ponyc's `builtin`
# path from its `Building` line must equal hefermotor's, and ponyc must
# print a group dump for it, or the run stops before any case is scored.
set -u

binary=${1:?usage: $0 <hefermotor binary> [case dir ...]}
shift
binary=$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")
here=$(cd "$(dirname "$0")" && pwd)
timeout_s=${DIFFERENTIAL_TIMEOUT:-600}

ponyc_bin=$(command -v ponyc) || { echo "no ponyc on PATH" >&2; exit 2; }
command -v python3 > /dev/null || { echo "no python3 on PATH" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

compared=0
agreed=0
differed=0
known=0
closed=0
crashed=0
not_compared=0
fp_agree=0
fp_total=0

# run_ponyc <cwd> <target> <verbosity> <pass> <out> <err>: ponyc's exit
# code.
run_ponyc() {
  (cd "$1" && timeout "$timeout_s" "$ponyc_bin" -V"$3" --pass="$4" "$2" \
    > "$5" 2> "$6")
}

# run_hefermotor <cwd> <target> <out> <err>: hefermotor's exit code.
run_hefermotor() {
  (cd "$1" && timeout "$timeout_s" "$binary" check "$2" --json \
    > "$3" 2> "$4")
}

# verdict_ponyc <code>
verdict_ponyc() {
  case "$1" in
    0) echo accept ;;
    255) echo reject ;;
    *) echo "crash($1)" ;;
  esac
}

# is_document <file>: whether the file is one format-1 document.
is_document() {
  grep -q '^{"format":1,"export_digest":"[0-9a-f]*",.*,"diagnostics":\[.*\]}$' \
    "$1"
}

# verdict_hefermotor <code> <document>
verdict_hefermotor() {
  case "$1" in
    0) is_document "$2" && echo accept || echo "crash(json)" ;;
    1) is_document "$2" && echo reject || echo "crash(json)" ;;
    2) echo abort ;;
    *) echo "crash($1)" ;;
  esac
}

# packages_from_building <ponyc stderr>: realpaths, sorted. ponyc prints
# one line per package, after its already-loaded check.
packages_from_building() {
  sed -n 's/^Building .* -> \(\/.*\)$/\1/p' "$1" | LC_ALL=C sort -u
}

# packages_from_json <document>: dirs, sorted; a repeated entry stays
# repeated so it shows.
packages_from_json() {
  grep -o '"dir":"[^"]*"' "$1" | sed 's/"dir":"//;s/"$//' | LC_ALL=C sort
}

# groups_from_reach <ponyc stdout>: one line per group, its members'
# basenames sorted and joined with spaces; lines sorted.
groups_from_reach() {
  awk '
    /^Group / { if (n) print_group(); n = 0; in_members = 0; next }
    /^Members:/ { in_members = 1; next }
    /^Dependencies:/ { in_members = 0; next }
    in_members && /^  / { sub(/^  /, ""); sub(/.*\//, ""); m[n++] = $0; next }
    END { if (n) print_group() }
    function print_group(   i, j, t, line) {
      for (i = 0; i < n; i++)
        for (j = i + 1; j < n; j++)
          if (m[j] < m[i]) { t = m[i]; m[i] = m[j]; m[j] = t }
      line = m[0]
      for (i = 1; i < n; i++) line = line " " m[i]
      print line
      delete m
    }' "$1" | LC_ALL=C sort
}

# groups_from_json <document>: the same shape from the document.
groups_from_json() {
  sed -n 's/.*"groups":\[\(.*\)\],"diagnostics".*/\1/p' "$1" \
    | sed 's/\],\[/\n/g; s/^\[//; s/\]$//' \
    | awk -F'","' '{
        n = 0
        for (i = 1; i <= NF; i++) {
          s = $i; gsub(/"/, "", s); sub(/.*\//, "", s); m[n++] = s
        }
        for (i = 0; i < n; i++)
          for (j = i + 1; j < n; j++)
            if (m[j] < m[i]) { t = m[i]; m[i] = m[j]; m[j] = t }
        line = m[0]
        for (i = 1; i < n; i++) line = line " " m[i]
        print line
        delete m
      }' | LC_ALL=C sort
}

# basenames_unique <document>: whether no two packages share a basename.
basenames_unique() {
  packages_from_json "$1" | sed 's|.*/||' | LC_ALL=C sort | uniq -d \
    | grep -q . && return 1 || return 0
}

# set_difference <ponyc lines> <hefermotor lines>: what only ponyc has,
# marked `ponyc:`, and what only hefermotor has, marked `hefermotor:`.
set_difference() {
  {
    LC_ALL=C comm -23 "$1" "$2" | sed 's/^/ponyc: /'
    LC_ALL=C comm -13 "$1" "$2" | sed 's/^/hefermotor: /'
  } | tr '\n' ' '
}

# positions_ponyc <ponyc stderr>: `<path>:<line>:<col>:` of every error
# line, sorted and unique.
positions_ponyc() {
  grep -oE '^/[^:]+:[0-9]+:[0-9]+:' "$1" | LC_ALL=C sort -u
}

# positions_hefermotor <document> <out>: the same for every `parse/`
# diagnostic, into `out`; false when `positions.py` fails.
positions_hefermotor() {
  python3 "$here/positions.py" "$1" > "$tmp/raw.pos" || return 1
  LC_ALL=C sort -u "$tmp/raw.pos" > "$2"
}

# lowest_position <positions>: the first by file, line and column.
lowest_position() {
  sort -t: -k1,1 -k2,2n -k3,3n "$1" | head -n 1
}

report() {
  local case_name=$1 outcome=$2 detail=$3
  echo "$outcome: $case_name${detail:+: $detail}"
}

# is_timeout <code>: whether `timeout` ended the command (124 from GNU,
# 143 from busybox).
is_timeout() {
  [ "$1" = 124 ] || [ "$1" = 143 ]
}

# score_case <working dir> <target> <name> <known gap classes or no>
# <kind>: `kind` is `syntax` for a fixture scored at `--pass=parse` on
# the verdict and positions, `program` for one scored at `--pass=scope`
# on the verdict, packages and groups.
score_case() {
  local dir=$1 target=$2 name=$3 gap=$4 kind=$5
  compared=$((compared + 1))
  local pv hv code missing n want pass=scope
  [ "$kind" = syntax ] && pass=parse
  run_ponyc "$dir" "$target" 2 "$pass" "$tmp/p.out" "$tmp/p.err"
  code=$?
  pv=$(verdict_ponyc "$code")
  run_hefermotor "$dir" "$target" "$tmp/h.json" "$tmp/h.err"
  code=$?
  hv=$(verdict_hefermotor "$code" "$tmp/h.json")
  local detail=""
  local outcome=agree
  case "$hv" in
    abort)
      echo "hefermotor could not start on $name:" >&2
      cat "$tmp/h.err" >&2
      exit 2 ;;
  esac
  case "$pv$hv" in
    *crash*) outcome=crash; detail="ponyc $pv, hefermotor $hv" ;;
  esac
  if [ "$outcome" = agree ] && [ "$pv" != "$hv" ]; then
    outcome=differ
    detail="verdict: ponyc $pv, hefermotor $hv"
  fi
  # The classes a difference falls in: the verdict, then the package
  # set and the group partition, or for a syntax case the positions and
  # their count.
  local classes=verdict
  if [ "$outcome" = agree ] && [ "$pv" = reject ] && [ "$kind" = syntax ]
  then
    classes=""
    positions_ponyc "$tmp/p.err" > "$tmp/p.pos"
    if ! positions_hefermotor "$tmp/h.json" "$tmp/h.pos"; then
      echo "positions.py failed on $name" >&2
      exit 2
    fi
    missing=$(LC_ALL=C comm -23 "$tmp/p.pos" "$tmp/h.pos" | tr '\n' ' ')
    if [ -n "$missing" ]; then
      outcome=differ
      classes="positions"
      detail="positions ponyc only: $missing"
    fi
    n=$(wc -l < "$tmp/h.pos")
    want=$(cat "$dir/EXPECT")
    if [ "$n" -ne "$want" ]; then
      outcome=differ
      classes="$classes count"
      detail="$detail${detail:+; }count: $n parse/ positions, EXPECT $want"
    fi
    fp_total=$((fp_total + 1))
    if [ "$(lowest_position "$tmp/p.pos")" = \
      "$(lowest_position "$tmp/h.pos")" ]
    then
      fp_agree=$((fp_agree + 1))
    fi
    [ "$outcome" = agree ] && detail="verdict and $n position(s)"
  fi
  if [ "$outcome" = agree ] && [ "$pv" = accept ] && [ "$kind" = syntax ]
  then
    classes=""
    want=$(cat "$dir/EXPECT")
    if [ "$want" -ne 0 ]; then
      outcome=differ
      classes=count
      detail="count: both accept, EXPECT $want"
    else
      detail="both accept"
    fi
  fi
  if [ "$outcome" = agree ] && [ "$pv" = accept ] && [ "$kind" = program ]
  then
    packages_from_building "$tmp/p.err" > "$tmp/p.pkgs"
    packages_from_json "$tmp/h.json" > "$tmp/h.pkgs"
    if ! cmp -s "$tmp/p.pkgs" "$tmp/h.pkgs"; then
      outcome=differ
      classes=packages
      detail="packages: $(set_difference "$tmp/p.pkgs" "$tmp/h.pkgs")"
    fi
  fi
  if [ "$outcome" = agree ] && [ "$pv" = accept ] && [ "$kind" = program ]
  then
    run_ponyc "$dir" "$target" 3 reach "$tmp/r.out" "$tmp/r.err"
    code=$?
    if is_timeout "$code"; then
      outcome=crash
      detail="ponyc --pass=reach timed out"
    elif grep -q '^Group 0' "$tmp/r.out"; then
      if basenames_unique "$tmp/h.json"; then
        groups_from_reach "$tmp/r.out" > "$tmp/p.groups"
        groups_from_json "$tmp/h.json" > "$tmp/h.groups"
        if ! cmp -s "$tmp/p.groups" "$tmp/h.groups"; then
          outcome=differ
          classes=groups
          detail="groups: $(set_difference "$tmp/p.groups" "$tmp/h.groups")"
        else
          detail="verdict, packages and $(wc -l < "$tmp/h.groups") group(s)"
        fi
      else
        not_compared=$((not_compared + 1))
        detail="verdict and packages; groups not compared (a basename repeats)"
      fi
    else
      not_compared=$((not_compared + 1))
      detail="verdict and packages; groups not compared (no dump)"
    fi
  fi
  case "$outcome" in
    agree)
      if [ "$gap" != no ]; then
        closed=$((closed + 1))
        report "$name" "known gap closed" "$detail"
      else
        agreed=$((agreed + 1))
        report "$name" agree "$detail"
      fi ;;
    differ)
      # shellcheck disable=SC2086
      if [ "$(printf '%s\n' $gap | LC_ALL=C sort)" = \
        "$(printf '%s\n' $classes | LC_ALL=C sort)" ]
      then
        known=$((known + 1))
        report "$name" "known gap" "$detail"
      else
        differed=$((differed + 1))
        report "$name" DIFFER "$detail"
      fi ;;
    crash)
      crashed=$((crashed + 1))
      report "$name" CRASH "$detail" ;;
  esac
}

# --- the sentinel ------------------------------------------------------

sentinel=$here/cases/sentinel
if ! run_ponyc "$sentinel" "$sentinel/main" 2 scope "$tmp/s.out" "$tmp/s.err"
then
  echo "sentinel: ponyc did not accept the sentinel:" >&2
  cat "$tmp/s.err" >&2
  exit 2
fi
ponyc_builtin=$(sed -n 's/^Building builtin -> \(.*\)$/\1/p' "$tmp/s.err")
run_ponyc "$sentinel" "$sentinel/main" 3 reach "$tmp/s.reach" "$tmp/s.rerr"
if ! grep -q '^Group 0' "$tmp/s.reach"; then
  echo "sentinel: ponyc printed no group dump for the sentinel:" >&2
  cat "$tmp/s.rerr" >&2
  exit 2
fi
if ! run_hefermotor "$sentinel" "$sentinel/main" "$tmp/s.json" "$tmp/s.herr"
then
  echo "sentinel: hefermotor did not accept the sentinel:" >&2
  cat "$tmp/s.herr" "$tmp/s.json" >&2
  exit 2
fi
hefermotor_builtin=$(packages_from_json "$tmp/s.json" | grep '/builtin$')
if [ -z "$ponyc_builtin" ] || [ "$ponyc_builtin" != "$hefermotor_builtin" ]; then
  echo "sentinel: builtin differs: ponyc used '$ponyc_builtin'," \
    "hefermotor used '$hefermotor_builtin'" >&2
  exit 2
fi
echo "sentinel: both use $ponyc_builtin"

# --- the cases ---------------------------------------------------------

# score_fixture <case dir>: a KNOWN_GAP file lists the classes expected
# to differ, one per line; a `syntax-` case holds an EXPECT file.
score_fixture() {
  local c gap kind word
  [ -d "$1" ] || { echo "no such case directory: $1" >&2; exit 2; }
  c=$(cd "$1" && pwd)
  kind=program
  case "$(basename "$c")" in
    syntax-*)
      kind=syntax
      if ! grep -qxE '[0-9]+' "$c/EXPECT" 2> /dev/null; then
        echo "$c/EXPECT must hold one integer" >&2
        exit 2
      fi ;;
  esac
  gap=no
  if [ -e "$c/KNOWN_GAP" ]; then
    gap=""
    while read -r word || [ -n "$word" ]; do
      case "$word" in
        verdict|packages|groups|positions|count) gap="$gap $word" ;;
        *) echo "$c/KNOWN_GAP must list verdict, packages, groups," \
             "positions or count, one per line" >&2
           exit 2 ;;
      esac
    done < "$c/KNOWN_GAP"
  fi
  score_case "$c" "$c/main" "$(basename "$c")" "$gap" "$kind"
}

if [ $# -gt 0 ]; then
  for c in "$@"; do score_fixture "$c"; done
else
  for c in "$here"/cases/*/; do score_fixture "${c%/}"; done
  packages=$(sed -n 's/^Building builtin -> \(.*\)\/builtin$/\1/p' "$tmp/s.err")
  work=$tmp/stdlib-cwd
  mkdir -p "$work"
  while read -r p; do
    score_case "$work" "$p" "stdlib/${p#"$packages"/}" no program
  done < <(find "$packages" -name '*.pony' -exec dirname {} \; \
    | LC_ALL=C sort -u)
fi

echo "differential: $compared compared, $agreed agree, $differed differ," \
  "$known known gaps, $closed known gaps closed, $crashed crashed," \
  "$not_compared groups not compared," \
  "first-position agree $fp_agree of $fp_total"
if [ "$differed" != 0 ] || [ "$crashed" != 0 ]; then exit 1; fi
