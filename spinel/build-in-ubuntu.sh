#!/usr/bin/env bash
# The Linux build, run as root in an ubuntu:26.04 container from the
# repository's root:
#
#   docker run --rm -v "$PWD:/src" -w /src ubuntu:26.04 bash spinel/build-in-ubuntu.sh
#
# Installs the compiler and the static libraries, builds Spinel and the
# statically linked sparoid, and gives build/ and dist/ to the checkout's owner.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -qq -y --no-install-recommends \
  ca-certificates curl git make gcc libc6-dev libcrypt-dev xz-utils \
  libssl-dev zlib1g-dev libzstd-dev libjitterentropy3-dev >/dev/null
trap 'chown -R "$(stat -c %u:%g .)" build dist 2>/dev/null' EXIT
bash spinel/install-spinel.sh build/spinel
bash spinel/build.sh
