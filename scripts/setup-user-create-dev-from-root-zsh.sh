#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-dev-from-root-zsh.sh
#
# Purpose  : Create 'dev' user, grant sudo & docker, set default shell to zsh,
#            and clone root's existing Zsh setup to dev (Oh My Zsh + config).
# Preconditions:
#   - Root already has Zsh set up and configured (e.g., /root/.oh-my-zsh, /root/.zshrc).
#   - No package installation or network access will be performed by this script.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Run as root.
# Idempotency:
#   - Safe to re-run; existing user and files are preserved or updated cautiously.
# Notes:
#   - Password is NOT set/changed here. Set it manually if needed: `passwd dev`.
# -----------------------------------------------------------------------------
set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }


# Require an existing zsh
if [[ ! -x /bin/zsh ]]; then
  echo "Error: /bin/zsh not found. Please install/configure zsh for root first." >&2
  exit 1
fi

# Paths
ROOT_HOME="/root"
DEV_USER="dev"
DEV_HOME="/home/${DEV_USER}"

# Ensure groups exist (no-op if they already do)
getent group sudo   >/dev/null 2>&1 || groupadd --system sudo
getent group docker >/dev/null 2>&1 || groupadd --system docker

# Create or normalize user
if id -u "${DEV_USER}" >/dev/null 2>&1; then
  echo ">>> User '${DEV_USER}' already exists. Ensuring shell & groups..."
  usermod -s /bin/zsh "${DEV_USER}" || true
else
  echo ">>> Creating user '${DEV_USER}'..."
  useradd -m -s /bin/zsh -G sudo,docker "${DEV_USER}"
fi
# Always (re)add to groups in case of prior state
usermod -aG sudo,docker "${DEV_USER}"

# Prepare dev home
mkdir -p "${DEV_HOME}"
chown -R "${DEV_USER}:${DEV_USER}" "${DEV_HOME}"

# --- Copy Zsh config from root to dev (no downloads, just local copy) ---

# 1) .zshrc: replace (backup once if present)
if [[ -f "${DEV_HOME}/.zshrc" && ! -f "${DEV_HOME}/.zshrc.bak" ]]; then
  cp -a "${DEV_HOME}/.zshrc" "${DEV_HOME}/.zshrc.bak"
fi
if [[ -f "${ROOT_HOME}/.zshrc" ]]; then
  cp -a "${ROOT_HOME}/.zshrc" "${DEV_HOME}/.zshrc"
  # In case the root config contains absolute /root paths, rewrite to /home/dev
  sed -i "s|/root|${DEV_HOME}|g" "${DEV_HOME}/.zshrc"
  chown "${DEV_USER}:${DEV_USER}" "${DEV_HOME}/.zshrc"
fi

# 2) .p10k.zsh: copy if root has it and dev doesn't
if [[ -f "${ROOT_HOME}/.p10k.zsh" && ! -f "${DEV_HOME}/.p10k.zsh" ]]; then
  cp -a "${ROOT_HOME}/.p10k.zsh" "${DEV_HOME}/.p10k.zsh"
  chown "${DEV_USER}:${DEV_USER}" "${DEV_HOME}/.p10k.zsh"
fi

# 3) Oh My Zsh directory:
#    - If dev doesn't have .oh-my-zsh, copy the whole tree from root.
#    - If dev already has it, ensure key addons (custom/plugins & custom/themes) match root.
if [[ -d "${ROOT_HOME}/.oh-my-zsh" ]]; then
  if [[ ! -d "${DEV_HOME}/.oh-my-zsh" ]]; then
    echo ">>> Cloning root's Oh My Zsh to dev..."
    cp -a "${ROOT_HOME}/.oh-my-zsh" "${DEV_HOME}/.oh-my-zsh"
    chown -R "${DEV_USER}:${DEV_USER}" "${DEV_HOME}/.oh-my-zsh"
  else
    echo ">>> Ensuring dev has root's plugins/themes (no overwrite of existing files)..."
    # Plugins we commonly rely on
    for p in zsh-autosuggestions zsh-syntax-highlighting; do
      if [[ -d "${ROOT_HOME}/.oh-my-zsh/custom/plugins/${p}" && ! -d "${DEV_HOME}/.oh-my-zsh/custom/plugins/${p}" ]]; then
        mkdir -p "${DEV_HOME}/.oh-my-zsh/custom/plugins"
        cp -a "${ROOT_HOME}/.oh-my-zsh/custom/plugins/${p}" "${DEV_HOME}/.oh-my-zsh/custom/plugins/${p}"
      fi
    done
    # Theme powerlevel10k
    if [[ -d "${ROOT_HOME}/.oh-my-zsh/custom/themes/powerlevel10k" && ! -d "${DEV_HOME}/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
      mkdir -p "${DEV_HOME}/.oh-my-zsh/custom/themes"
      cp -a "${ROOT_HOME}/.oh-my-zsh/custom/themes/powerlevel10k" "${DEV_HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
    fi
    chown -R "${DEV_USER}:${DEV_USER}" "${DEV_HOME}/.oh-my-zsh"
  fi
fi

# Final ownership pass (in case of partial copies)
chown -R "${DEV_USER}:${DEV_USER}" "${DEV_HOME}"

echo "------------------------------------------------------------"
echo "User   : ${DEV_USER}"
echo "Home   : ${DEV_HOME}"
echo "Shell  : /bin/zsh"
echo "Groups : $(id -nG "${DEV_USER}")"
echo "Zsh    : Config copied from ${ROOT_HOME} (if present)."
echo "Done. You can now 'su - ${DEV_USER}'"
echo "Tip: Set a password if needed: 'passwd ${DEV_USER}'"
