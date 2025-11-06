#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-ssh-defaults.sh
#
# Purpose  : Ensure ~/.ssh is correctly set up for a user:
#            - Create ~/.ssh with strict perms
#            - Write a managed SSH config block
#            - Generate an Ed25519 keypair if missing
#            - Ensure the public key is in authorized_keys (deduped)
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root. By default targets $SUDO_USER if set, else root.
# Features :
#   - Idempotent (safe to re-run)
#   - Optional: --target-user <USER> to operate on another user's ~/.ssh
# Usage    :
#   sudo -i
#   bash setup-ssh-defaults.sh [--target-user dev]
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- root requirement --------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root (e.g., sudo -i && bash setup-ssh-defaults.sh)." >&2
  exit 1
fi

# ---- parse args (only --target-user, keep it simple) -------------------------
TARGET_USER="${SUDO_USER:-root}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-user) shift; TARGET_USER="${1:-$TARGET_USER}";;
    -h|--help)
      cat <<'EOF'
Usage:
  setup-ssh-defaults.sh [--target-user USER]
Notes:
  - Operates on $SUDO_USER if present; otherwise on root.
  - Creates ~/.ssh (700), config (managed block, 600), authorized_keys (600).
  - Generates Ed25519 key (~/.ssh/id_ed25519) if missing (-a 100, empty passphrase).
  - Ensures the public key is present in authorized_keys (deduped).
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift || true
done

# ---- resolve target user/home/ownership -------------------------------------
if ! getent passwd "${TARGET_USER}" >/dev/null 2>&1; then
  echo "Cannot resolve user: ${TARGET_USER}" >&2
  exit 1
fi
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
OWNER_USER="${TARGET_USER}"
OWNER_GROUP="$(id -gn "${TARGET_USER}")"

SSH_DIR="${TARGET_HOME}/.ssh"
CONFIG_PATH="${SSH_DIR}/config"
AUTH_KEYS="${SSH_DIR}/authorized_keys"
PRIV_KEY="${SSH_DIR}/id_ed25519"
PUB_KEY="${SSH_DIR}/id_ed25519.pub"
MARK_BEGIN="# BEGIN setup-ssh-defaults"
MARK_END="# END setup-ssh-defaults"

# ---- create ~/.ssh and set perms ---------------------------------------------
umask 077
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
chown "${OWNER_USER}:${OWNER_GROUP}" "${SSH_DIR}"

# ---- backup config once if present -------------------------------------------
if [[ -f "${CONFIG_PATH}" && ! -f "${CONFIG_PATH}.bak" ]]; then
  cp -p "${CONFIG_PATH}" "${CONFIG_PATH}.bak"
fi

# ---- remove previous managed block and rewrite -------------------------------
if [[ -f "${CONFIG_PATH}" ]]; then
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    BEGIN{inblk=0}
    $0~b{inblk=1;next}
    $0~e{inblk=0;next}
    !inblk{print}
  ' "${CONFIG_PATH}" > "${CONFIG_PATH}.tmp"
  mv "${CONFIG_PATH}.tmp" "${CONFIG_PATH}"
else
  : > "${CONFIG_PATH}"
fi

cat >> "${CONFIG_PATH}" <<'EOF'
# BEGIN setup-ssh-defaults
Host *
    ControlPath /tmp/ssh-%r@%h:%p
    ControlMaster auto
    ControlPersist 1h
    TCPKeepAlive no
    ServerAliveInterval 60
# END setup-ssh-defaults
EOF

chmod 600 "${CONFIG_PATH}"
chown "${OWNER_USER}:${OWNER_GROUP}" "${CONFIG_PATH}"

# ---- ensure authorized_keys --------------------------------------------------
touch "${AUTH_KEYS}"
chmod 600 "${AUTH_KEYS}"
chown "${OWNER_USER}:${OWNER_GROUP}" "${AUTH_KEYS}"

# ---- generate Ed25519 keypair if missing ------------------------------------
if [[ ! -f "${PRIV_KEY}" || ! -f "${PUB_KEY}" ]]; then
  COMMENT="${OWNER_USER}@$(hostname -f 2>/dev/null || hostname)"
  if [[ "$(id -un)" == "${OWNER_USER}" ]]; then
    ssh-keygen -t ed25519 -a 100 -f "${PRIV_KEY}" -N "" -C "${COMMENT}" >/dev/null
  else
    su - "${OWNER_USER}" -s /bin/bash -c "ssh-keygen -t ed25519 -a 100 -f '${PRIV_KEY}' -N '' -C '${COMMENT}' >/dev/null"
  fi
  echo "Generated new Ed25519 keypair at ${PRIV_KEY}"
fi

# ---- ensure the public key is in authorized_keys (dedup) ---------------------
if [[ -f "${PUB_KEY}" ]]; then
  PUB_CONTENT="$(cat "${PUB_KEY}")"
  if ! grep -qxF -- "${PUB_CONTENT}" "${AUTH_KEYS}"; then
    printf '%s\n' "${PUB_CONTENT}" >> "${AUTH_KEYS}"
  fi
fi

# ---- final ownership ---------------------------------------------------------
chown "${OWNER_USER}:${OWNER_GROUP}" "${AUTH_KEYS}"
chown -R "${OWNER_USER}:${OWNER_GROUP}" "${SSH_DIR}"

echo "SSH config updated: ${CONFIG_PATH}"
echo "authorized_keys ready: ${AUTH_KEYS}"
[[ -f "${PUB_KEY}" ]] && echo "Public key: ${PUB_KEY}"
echo "Target user: ${OWNER_USER} (home: ${TARGET_HOME})"
echo "Done."
