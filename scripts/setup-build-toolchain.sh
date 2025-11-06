#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-build-toolchain.sh
#
# Purpose  : Install a comprehensive build toolchain for common C/C++/Rust/Node/Python builds.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root.
# Features :
#   - Compilers & linkers: gcc/g++/gfortran, clang/llvm, lld, (mold if available)
#   - Build tools: make, CMake, Ninja, pkg-config, Autotools (autoconf/automake/libtool), m4
#   - Assemblers & helpers: nasm, yasm, ccache, binutils, patchelf
#   - VCS & basics: git, git-lfs, curl, wget, unzip, xz-utils, zip, ca-certificates
#   - Python & headers for node-gyp/Python builds: python3, python3-dev, python3-venv, python3-pip
#   - Common dev libraries/headers: OpenSSL, zlib, bz2, lzma, readline, sqlite3, ffi, ncurses, tk, XML/XSLT, cURL
#   - Idempotent: safe to re-run; prints versions for verification
# Usage    :
#   sudo -i
#   bash setup-build-toolchain.sh
# Notes    :
#   - Some extras (e.g., mold) may not be in all mirrors; install attempts are best-effort.
# -----------------------------------------------------------------------------

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root (e.g., sudo -i && bash setup-build-toolchain.sh)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo ">>> Enabling required apt components..."
apt-get update -y
apt-get install -y --no-install-recommends software-properties-common
add-apt-repository -y universe || true
apt-get update -y

echo ">>> Installing core compilers, linkers, and build tools..."
apt-get install -y --no-install-recommends \
  build-essential pkg-config \
  gcc g++ gfortran \
  clang llvm lld lldb \
  cmake ninja-build make \
  autoconf automake libtool m4 \
  nasm yasm ccache \
  binutils patchelf \
  git git-lfs \
  curl wget ca-certificates \
  unzip xz-utils tar zip \
  python3 python3-dev python3-venv python3-pip \
  libssl-dev zlib1g-dev libbz2-dev liblzma-dev \
  libreadline-dev libsqlite3-dev libffi-dev \
  libncurses5-dev libncursesw5-dev tk-dev \
  libxml2-dev libxslt1-dev libcurl4-openssl-dev

# Optional extras (best-effort; don’t fail the script if unavailable)
apt-get install -y --no-install-recommends mold || true

# Git LFS init (idempotent)
if command -v git-lfs >/dev/null 2>&1; then
  git lfs install --system || true
fi

echo ">>> Versions (verification):"
{ gcc --version | head -n1; }        || true
{ g++ --version | head -n1; }        || true
{ gfortran --version | head -n1; }   || true
{ clang --version | head -n1; }      || true
{ lld --version | head -n1; }        || true
{ lldb --version | head -n1; }       || true
{ mold --version | head -n1; }       || echo "mold not installed (optional)"
{ cmake --version | head -n1; }      || true
{ ninja --version | head -n1; }      || true
{ make --version | head -n1; }       || true
{ pkg-config --version; }            || true
{ autoconf --version | head -n1; }   || true
{ automake --version | head -n1; }   || true
{ libtool --version | head -n1; }    || true
{ nasm -v | head -n1; }              || true
{ yasm --version | head -n1; }       || true
{ ccache --version | head -n1; }     || true
{ git --version; }                   || true
{ git-lfs --version; }               || true
{ python3 --version; }               || true
{ pip3 --version; }                  || true
{ openssl version; }                 || true

echo "✅ Build toolchain ready."
