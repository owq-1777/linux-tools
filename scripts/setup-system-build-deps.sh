#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-system-build-deps.sh
#
# Purpose  : Install system-wide build deps and Go toolchain (optional, fixed version).
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root.
# Features :
#   - Installs build-essential, pkg-config, git, curl, ca-certificates, unzip, xz-utils, tar
#   - Installs Go under /usr/local/go (idempotent; existing moved to .bak.<ts>)
#   - Adds /usr/local/go/bin to system PATH via /etc/profile.d
#   - Prints versions for verification
# Usage    :
#   sudo -i
#   bash setup-system-build-deps.sh
# Notes    :
#   - Adjust GO_VERSION if needed.
# -----------------------------------------------------------------------------

set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }

export DEBIAN_FRONTEND=noninteractive
GO_VERSION="1.25.4"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"

echo ">>> Installing base packages..."
apt-get update -y
apt-get install -y build-essential pkg-config git curl ca-certificates unzip xz-utils tar

echo ">>> Installing Go ${GO_VERSION} to /usr/local/go ..."
TMPDIR="$(mktemp -d)"
cd "${TMPDIR}"
curl -fL "${GO_URL}" -o "${GO_TARBALL}"
if [[ -d /usr/local/go ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  mv -v /usr/local/go "/usr/local/go.bak.${TS}"
fi
tar -C /usr/local -xzf "${GO_TARBALL}"

echo ">>> Ensuring system PATH has /usr/local/go/bin ..."
install -m 0644 /dev/stdin /etc/profile.d/go-path.sh <<'EOF'
# /etc/profile.d/go-path.sh - managed
if [ -d /usr/local/go/bin ] && ! echo ":$PATH:" | grep -q ':/usr/local/go/bin:'; then
  export PATH="/usr/local/go/bin:$PATH"
fi
EOF

# --- Versions (verification) ---
echo ">>> Versions:"
git --version || true
gcc --version | head -n1 || true
g++ --version | head -n1 || true
make --version | head -n1 || true
pkg-config --version || true
curl --version | head -n1 || true
source /etc/profile.d/go-path.sh || true
go version || true

echo "✅ System build deps ready."
