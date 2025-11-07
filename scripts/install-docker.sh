#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install-docker.sh
#
# Purpose  : Install Docker Engine (CE) for root on Ubuntu using the official apt repo.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root (affects the system-wide Docker service).
# Features :
#   - Removes conflicting packages from Ubuntu repos (docker.io, etc.)
#   - Adds Docker's official apt repository and GPG key
#   - Installs: docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin
#   - Enables and starts the Docker service
#   - Idempotent (safe to re-run)
# Notes    :
#   - Official steps & repo lines follow Docker docs:
#       https://docs.docker.com/engine/install/ubuntu/
# -----------------------------------------------------------------------------

set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo ">>> Removing conflicting packages (if any)..."
# From Docker docs: uninstall unofficial/conflicting packages before install.
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done

echo ">>> Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates curl

echo ">>> Setting up Docker apt repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

UBUNTU_CODE_NAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
ARCH="$(dpkg --print-architecture)"

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODE_NAME} stable
EOF

echo ">>> Installing Docker Engine & plugins..."
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ">>> Enabling and starting Docker service..."
systemctl enable --now docker

# Optional: provide a compatibility wrapper for "docker-compose" if users still type it
if [[ ! -x /usr/local/bin/docker-compose ]]; then
  cat > /usr/local/bin/docker-compose <<'SH'
#!/usr/bin/env bash
exec docker compose "$@"
SH
  chmod +x /usr/local/bin/docker-compose
fi

echo ">>> Versions:"
docker --version || true
docker compose version || true

cat <<'EOM'

✅ Docker installation complete.

Quick checks:
  - 'docker --version'
  - 'docker compose version'
  - (Optional) Run a test image: 'docker run --rm hello-world'

Notes:
  - Docker service is enabled at boot and running now.
  - For non-root usage, add a user to the 'docker' group and re-login:
      usermod -aG docker <username>
EOM
