#!/usr/bin/env bash
# One digest per package under a packages directory of the non-trivia
# token kinds of its files, written as `<out dir>/<package>` with the
# package's path under the directory joined by `_`.
#
# Usage: tools/syntax/token_digest.sh <syntax binary> <packages dir> <out dir>
set -euo pipefail

syntax=${1:?usage: $0 <syntax binary> <packages dir> <out dir>}
packages=${2:?usage: $0 <syntax binary> <packages dir> <out dir>}
out=${3:?usage: $0 <syntax binary> <packages dir> <out dir>}
packages=${packages%/}

mkdir -p "$out"
while read -r dir; do
  pkg=$(echo "${dir#"$packages"/}" | tr / _)
  find "$dir" -maxdepth 1 -name '*.pony' | LC_ALL=C sort \
    | xargs "$syntax" --tokens | sed 's|^### .*/|### |' \
    | sha256sum | cut -d' ' -f1 > "$out/$pkg"
done < <(find "$packages" -name '*.pony' -exec dirname {} \; \
  | LC_ALL=C sort -u)
