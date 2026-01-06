#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-system-build-toolchain.sh
#
# Purpose  : Install a comprehensive build toolchain for common C/C++/Rust/Node/Python builds.
# OS       : Ubuntu 22.04 (Jammy) / 24.04 (Noble) - 64-bit
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
#   bash setup-system-build-toolchain.sh
# Notes    :
#   - Some extras (e.g., mold) may not be in all mirrors; install attempts are best-effort.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/os.sh"
require_supported_ubuntu
ensure_apt_ready

[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }


export DEBIAN_FRONTEND=noninteractive

echo ">>> Enabling required apt components..."
apt-get update -y
apt-get install -y --no-install-recommends software-properties-common
add-apt-repository -y universe || true
apt-get update -y

echo ">>> Installing core compilers, linkers, and build tools..."
filter_available() {
  local out=()
  for pkg in "$@"; do
    if apt-cache policy "$pkg" 2>/dev/null | awk -F': ' '/Candidate:/ {print $2}' | grep -qv '(none)'; then
      out+=("$pkg")
    fi
  done
  printf '%s\n' "${out[@]}"
}
pkgs=(
  build-essential pkg-config
  gcc g++ gfortran
  clang llvm lld lldb
  cmake ninja-build make
  autoconf automake libtool m4
  nasm yasm ccache
  binutils patchelf
  git git-lfs
  curl wget ca-certificates
  unzip xz-utils tar zip
  python3 python3-dev python3-venv python3-pip
  libssl-dev zlib1g-dev libbz2-dev liblzma-dev
  libreadline-dev libsqlite3-dev libffi-dev
  libncurses5-dev libncursesw5-dev tk-dev
  libxml2-dev libxslt1-dev libcurl4-openssl-dev
)
mapfile -t avail_pkgs < <(filter_available "${pkgs[@]}")
apt-get install -y --no-install-recommends "${avail_pkgs[@]}"

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
