#!/usr/bin/env bash
# Build the Spinel compiler that spinel-version pins into DIR (default
# build/spinel); DIR/bin/spinel then compiles sparoid (build.sh).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dir=${1:-$here/../build/spinel}
ref=$(cat "$here/spinel-version")

if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$ref" ]; then
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" fetch -q --depth 1 https://github.com/matz/spinel.git "$ref"
  git -C "$dir" checkout -q FETCH_HEAD
fi
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
make -C "$dir" -s deps
make -C "$dir" -s -j"$jobs"
"$dir/bin/spinel" --version
