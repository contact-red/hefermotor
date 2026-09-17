#!/usr/bin/env bash
# Determinism harness: the same input gives the same document, and a
# package's export hash does not depend on where the package sits.
#
# Usage: tools/determinism/check.sh <hefermotor binary>
#
# Two checks. First, two `--json` runs over `stdlib`, found through the
# search roots as ponyc finds it, must be byte-identical. Second, a small
# fixture is laid out three ways and the `export_digest` of the first
# layout must equal the other two: layout 2 is layout 1 copied under a directory with a
# different name, which permutes paths and nothing else; layout 3 swaps
# the two dependencies between the two search roots, which flips
# `PackageDir` order and so the root's dependency order and the group's
# member order while every locator still resolves. On a mismatch the
# first package (by name) whose `export_hash` differs is named.
#
# The fixture's own stub `builtin/` sits in each layout's base directory,
# where it shadows the stdlib slot, so the fixture runs with no ponyc
# packages at all. Each run is limited to DETERMINISM_TIMEOUT seconds
# (default 600).
set -u

binary=${1:?usage: $0 <hefermotor binary>}
binary=$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")
timeout_s=${DETERMINISM_TIMEOUT:-600}
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- stdlib: two runs, one document -----------------------------------

(cd "$tmp" && timeout "$timeout_s" "$binary" check stdlib --json) \
  > "$tmp/stdlib-1.json"
code1=$?
(cd "$tmp" && timeout "$timeout_s" "$binary" check stdlib --json) \
  > "$tmp/stdlib-2.json"
code2=$?
if [ "$code1" != 0 ] || [ "$code2" != 0 ]; then
  fail "stdlib: exit codes $code1 and $code2, expected 0 and 0"
elif ! cmp -s "$tmp/stdlib-1.json" "$tmp/stdlib-2.json"; then
  fail "stdlib: two runs gave different documents"
  diff "$tmp/stdlib-1.json" "$tmp/stdlib-2.json" >&2 || true
else
  echo "ok: stdlib: two runs, one document"
fi

# --- fixture: three layouts, one digest -------------------------------

# lay_out <dir> <root holding a> <root holding b>: the fixture with `a`
# under the first root and `b` under the second.
lay_out() {
  local dir=$1 a_root=$2 b_root=$3
  mkdir -p "$dir/$a_root/a" "$dir/$b_root/b" "$dir/r" "$dir/builtin"
  printf 'use "b"\nprimitive A\n' > "$dir/$a_root/a/a.pony"
  printf 'use "a"\nprimitive B\n' > "$dir/$b_root/b/b.pony"
  printf 'use "a"\nuse "b"\nprimitive R\n' > "$dir/r/r.pony"
  printf 'primitive None\n' > "$dir/builtin/builtin.pony"
}

# run_layout <dir>: the document for a layout, with the base directory
# the layout itself so its `builtin/` shadows the slot.
run_layout() {
  local dir=$1
  (cd "$dir" && timeout "$timeout_s" "$binary" check r --path="$dir/p" \
    --path="$dir/q" --json)
}

digest_of() {
  sed -n 's/.*"export_digest":"\([0-9a-f]*\)".*/\1/p' "$1"
}

# hashes_of <document>: one "name hash" line per package, sorted by
# name; a package without an export has `null` for its hash.
hashes_of() {
  grep -o '"name":"[^"]*","group":[0-9]*,"export_hash":\("[0-9a-f]*"\|null\)' \
    "$1" \
    | sed 's/"name":"//; s/","group":[0-9]*,"export_hash":/ /; s/"//g' \
    | LC_ALL=C sort
}

lay_out "$tmp/one" p q
mkdir -p "$tmp/copy"
cp -R "$tmp/one" "$tmp/copy/elsewhere"
lay_out "$tmp/three" q p

run_layout "$tmp/one" > "$tmp/one.json" || fail "layout 1: exit $?"
run_layout "$tmp/copy/elsewhere" > "$tmp/two.json" || fail "layout 2: exit $?"
run_layout "$tmp/three" > "$tmp/three.json" || fail "layout 3: exit $?"

compare_layout() {
  local what=$1 first=$2 other=$3
  local d1 d2
  d1=$(digest_of "$first")
  d2=$(digest_of "$other")
  if [ -z "$d1" ] || [ -z "$d2" ]; then
    fail "$what: a document has no export_digest"
    return
  fi
  if [ "$d1" = "$d2" ]; then
    echo "ok: $what: export_digest $d1"
    return
  fi
  fail "$what: export_digest $d1 != $d2"
  hashes_of "$first" > "$tmp/h1"
  hashes_of "$other" > "$tmp/h2"
  # The first package whose hash differs, by name.
  local name h1 h2
  while read -r name h1; do
    h2=$(awk -v n="$name" '$1 == n { print $2 }' "$tmp/h2")
    if [ "$h1" != "$h2" ]; then
      echo "  first difference: $name: $h1 vs ${h2:-absent}" >&2
      return
    fi
  done < "$tmp/h1"
  echo "  every package hash matches; the package sets differ" >&2
}

compare_layout "layout 2 (paths permuted)" "$tmp/one.json" "$tmp/two.json"
compare_layout "layout 3 (dependency and member order permuted)" \
  "$tmp/one.json" "$tmp/three.json"

# Unless layout 3 changed the group's member order, the digest
# comparison above tested nothing about member order: the group listing
# by package name must differ between layouts 1 and 3.
groups_by_name() {
  sed -n 's/.*"groups":\[\(.*\)\],"diagnostics".*/\1/p' "$1" \
    | sed 's|"[^"]*/\([^"/]*\)"|"\1"|g'
}
if [ "$(groups_by_name "$tmp/one.json")" = "$(groups_by_name "$tmp/three.json")" ]
then
  fail "layout 3 left the member order unchanged; it permutes nothing" \
    "that layout 2 does not"
fi

if [ "$failures" != 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "determinism: all checks passed"
