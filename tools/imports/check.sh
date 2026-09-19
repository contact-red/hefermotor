#!/usr/bin/env bash
#   check.sh <root> <deps.txt>
#
# Walks every .pony file under <root> and reports each line that breaks
# one of five rules, as `path:line: rule N: message`, with the path
# relative to <root>. Exits 1 if anything was reported, 0 otherwise, and
# 2 if deps.txt is malformed.
#
# 1. Every `use` target must be on the file's line in deps.txt, or on
#    its package's line when the file has no line of its own; a
#    _test.pony file with no line of its own may also use pony_test and
#    pony_check. A package on the `!banned` line is rejected everywhere.
# 2. `use @` is allowed only in a file whose line says `@`.
# 3. An FFI call, `@name` or `@"name"` followed by `(` or `[`, is
#    allowed only in a file whose line says `@`.
# 4. `digestof`, `MapIs`, `SetIs`, `HashIs` and `Pointer[` are rejected
#    in a non-_test.pony file of a package or file on the `!phase` line,
#    or of a package below one on that line.
# 5. `.hash()` is rejected in a file on the `!hash64-only` line.
#
# A package's key is its directory relative to <root> with a leading
# `hefermotor/` removed, so `hefermotor/source` is `source` and the
# umbrella and the binary are `hefermotor` and `hefermotor_main`. A
# file's key is `<package key>/<file name>`; a key starting with `*/`
# matches that file name in every package. Text inside `"""` blocks,
# inside string literals, and after `//` is not scanned, and whitespace
# between the tokens of a `use` line or an FFI call does not hide it.
# `<root>/build`, `<root>/_corral`, `<root>/tools/imports/testdata`,
# `<root>/tools/differential/cases` and `<root>/tools/syntax/fixtures`
# are not walked.
#
# This is a check against mistakes, not a proof: a line shaped so that
# no rule's pattern matches it is not reported.

set -euo pipefail

root=${1:?usage: check.sh <root> <deps.txt>}
deps=${2:?usage: check.sh <root> <deps.txt>}
root=${root%/}

# Join continuation lines and drop comments, giving `key<TAB>values`
# with the key and each value trimmed; refuse a table that would
# silently grant something.
table=$(awk '
  BEGIN { known["!banned"]; known["!phase"]; known["!hash64-only"] }
  function flush() {
    if (key == "") return
    gsub(/^[ \t]+|[ \t]+$/, "", key)
    gsub(/[ \t]+/, " ", rest); gsub(/^ | $/, "", rest)
    if (key in seen) { print "duplicate key " key > "/dev/stderr"; bad = 1 }
    seen[key] = 1
    if (key ~ /^!/ && rest == "") {
      print "empty directive " key > "/dev/stderr"; bad = 1 }
    if (key ~ /^!/ && !(key in known)) {
      print "unknown directive " key > "/dev/stderr"; bad = 1 }
    printf "%s\t%s\n", key, rest
  }
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  /^[[:space:]]/ { rest = rest " " $0; next }
  { flush()
    key = $0; sub(/:.*/, "", key)
    rest = $0; sub(/^[^:]*:/, "", rest) }
  END { flush(); if (bad) exit 2 }
' "$deps") || { echo "check.sh: malformed $deps" >&2; exit 2; }

# Prints a key's values, or nothing when the key has no line. A key with
# an empty value string prints a single space so the two can be told
# apart.
lookup() {
  local key=$1
  printf '%s\n' "$table" \
    | awk -F'\t' -v k="$key" '$1 == k { print ($2 == "" ? " " : $2); exit }'
}

banned=$(lookup '!banned')
phase=$(lookup '!phase')
hash64only=$(lookup '!hash64-only')

has_word() {
  local list=$1 word=$2
  [ -n "$word" ] || return 1
  printf ' %s ' "$list" | grep -qF " $word "
}

# True when `key` is on the !phase line, or is under a package that is.
in_phase_list() {
  local key=$1 entry
  for entry in $phase; do
    case "$key" in
      "$entry"|"$entry"/*) return 0 ;;
    esac
  done
  return 1
}

# Collapse `.` and `..` segments lexically; nothing here touches the
# file system, so the result is the same on every platform.
normalize() {
  printf '%s\n' "$1" | awk -F/ '
    { n = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "" || $i == ".") continue
        if ($i == "..") { if (n > 0) n--; continue }
        parts[++n] = $i
      }
      s = ""
      for (i = 1; i <= n; i++) s = s (i > 1 ? "/" : "") parts[i]
      print s }'
}

findings=$(mktemp)
trap 'rm -f "$findings"' EXIT

while IFS= read -r file; do
  rel=${file#"$root"/}
  dir=$(dirname "$rel")
  base=$(basename "$rel")
  pkg=${dir#hefermotor/}
  if [ "$pkg" = "." ]; then pkg=""; fi
  filekey="$pkg/$base"
  glob="*/$base"

  allowed=$(lookup "$filekey")
  if [ -z "$allowed" ]; then allowed=$(lookup "$glob"); fi
  if [ -z "$allowed" ]; then
    allowed=$(lookup "$pkg")
    if [ "$base" = "_test.pony" ]; then
      allowed="$allowed pony_test pony_check"
    fi
  fi
  ffi_ok=false
  if has_word "$allowed" "@"; then ffi_ok=true; fi
  in_phase=false
  if [ "$base" != "_test.pony" ] \
    && { in_phase_list "$pkg" || in_phase_list "$filekey"; }; then
    in_phase=true
  fi
  hash64=false
  if has_word "$hash64only" "$filekey"; then hash64=true; fi

  # Emit one line per source line as `lineno<TAB>text`, with docstrings,
  # string literals and comments blanked in one left-to-right scan that
  # carries the docstring state across lines. A string literal's quotes
  # are kept so a `use` line keeps its shape.
  awk '
    { line = $0; out = ""; n = length(line); i = 1
      while (i <= n) {
        if (indoc) {
          j = index(substr(line, i), "\"\"\"")
          if (j == 0) { i = n + 1 }
          else { i = i + j + 2; indoc = 0 }
        } else if (substr(line, i, 3) == "\"\"\"") {
          indoc = 1; i += 3
        } else if (substr(line, i, 2) == "//") {
          i = n + 1
        } else if (substr(line, i, 1) == "\"") {
          out = out "\""; i++
          while (i <= n && substr(line, i, 1) != "\"") {
            if (substr(line, i, 1) == "\\") i++
            out = out "?"; i++
          }
          out = out "\""; i++
        } else {
          out = out substr(line, i, 1); i++
        }
      }
      printf "%d\t%s\n", NR, out }
  ' "$file" | while IFS=$'\t' read -r lineno text; do
    trimmed=${text#"${text%%[![:space:]]*}"}
    case "$trimmed" in
      use[[:space:]]*@*|use@*)
        if ! $ffi_ok; then
          echo "$rel:$lineno: rule 2: use @ in a file whose line lacks @"
        fi
        continue
        ;;
      use[[:space:]]*|use\"*)
        # The scan replaced the locator's characters with `?`; read the
        # real text from the source line by its column.
        span=$(printf '%s' "$trimmed" \
          | sed -n 's/^use[^"]*\("[?]*"\).*/\1/p')
        if [ -z "$span" ]; then continue; fi
        locator=$(sed -n "${lineno}p" "$file" \
          | sed -n 's/^[[:space:]]*use[^"]*"\([^"]*\)".*/\1/p')
        if [ -z "$locator" ]; then continue; fi
        case "$locator" in
          ./*|../*)
            target=$(normalize "$dir/$locator")
            target=${target#hefermotor/}
            ;;
          *) target=$locator ;;
        esac
        if has_word "$banned" "$target"; then
          echo "$rel:$lineno: rule 1: use of banned package $target"
        elif ! has_word "$allowed" "$target"; then
          echo "$rel:$lineno: rule 1: use of $target not on the file's line"
        fi
        continue
        ;;
    esac
    if ! $ffi_ok && printf '%s' "$text" \
      | grep -qE '@[[:space:]]*("[?]*"|[A-Za-z_][A-Za-z0-9_]*)[[:space:]]*[([]'
    then
      echo "$rel:$lineno: rule 3: FFI call in a file whose line lacks @"
    fi
    if $in_phase && printf '%s' "$text" \
      | grep -qE \
        '(^|[^A-Za-z0-9_])(digestof|MapIs|SetIs|HashIs|Pointer[[:space:]]*\[)'
    then
      echo "$rel:$lineno: rule 4: hashing by address in a phase file"
    fi
    if $hash64 && printf '%s' "$text" \
      | grep -qE '\.hash[[:space:]]*\([[:space:]]*\)'
    then
      echo "$rel:$lineno: rule 5: .hash() where only hash64 is allowed"
    fi
  done >> "$findings"
done < <(find "$root" -name '*.pony' \
  -not -path "$root/_corral/*" -not -path "$root/build/*" \
  -not -path "$root/tools/imports/testdata/*" \
  -not -path "$root/tools/differential/cases/*" \
  -not -path "$root/tools/syntax/fixtures/*" | LC_ALL=C sort)

if [ -s "$findings" ]; then
  LC_ALL=C sort "$findings"
  exit 1
fi
