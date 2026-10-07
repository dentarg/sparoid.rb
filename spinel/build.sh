#!/usr/bin/env bash
# Compile sparoid with Spinel into one executable that needs no Ruby, check
# it, and package it as dist/sparoid-VERSION-OS-ARCH.tar.gz (+ .sha256).
#
# Linux: statically linked, runs on any distribution of the same CPU
# architecture (glibc or musl). Build it where libcrypto.a and the static
# libraries main_static.rb names exist (build-in-ubuntu.sh).
# macOS: OpenSSL linked statically from Homebrew's openssl@3, the rest from
# the system.
#
# Env: SPINEL (default build/spinel/bin/spinel, see install-spinel.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
SPINEL=${SPINEL:-$PWD/build/spinel/bin/spinel}
version=$(sed -n 's/^ *VERSION = "\(.*\)"$/\1/p' lib/sparoid/version.rb)
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
[ "$arch" = aarch64 ] && arch=arm64
bin=build/sparoid
mkdir -p build dist
rm -f "$bin"

case $os in
  linux)
    "$SPINEL" spinel/main_static.rb -o "$bin" --link -static
    strip "$bin"
    if ldd "$bin" 2>&1 | grep -q '=>'; then
      echo "build.sh: $bin is dynamically linked" >&2
      exit 1
    fi
    ;;
  darwin)
    # The archives as link inputs: Spinel then leaves out -lssl/-lcrypto,
    # which would pick Homebrew's dylibs, so the executable doesn't need
    # Homebrew's OpenSSL at run time (ld64 has no archive order to respect)
    openssl=$(brew --prefix openssl@3)
    "$SPINEL" spinel/main.rb -o "$bin" --link "$openssl/lib/libssl.a" --link "$openssl/lib/libcrypto.a"
    strip "$bin"
    if otool -L "$bin" | grep -q -e libssl -e libcrypto; then
      echo "build.sh: $bin links OpenSSL dynamically" >&2
      exit 1
    fi
    ;;
  *)
    echo "build.sh: no build for $os" >&2
    exit 1
    ;;
esac

[ "$("$bin" --version)" = "$version" ] || { echo "build.sh: $bin --version is not $version" >&2; exit 1; }
"$bin" keygen | grep -q '^hmac-key = [0-9a-f]\{64\}$' || { echo "build.sh: $bin keygen failed" >&2; exit 1; }

name=sparoid-$version-$os-$arch.tar.gz
tar -czf "dist/$name" -C build sparoid -C .. LICENSE.txt
if command -v sha256sum >/dev/null; then
  (cd dist && sha256sum "$name" >"$name.sha256")
else
  (cd dist && shasum -a 256 "$name" >"$name.sha256")
fi
cat "dist/$name.sha256"
