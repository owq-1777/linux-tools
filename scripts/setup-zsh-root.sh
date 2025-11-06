#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-zsh-root.sh
#
# Purpose  : Install Zsh, Oh My Zsh (for root), plugins, and Powerlevel10k.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root (affects only the root account).
# Features :
#   - Installs Zsh + Oh My Zsh under /root
#   - Plugins: zsh-autosuggestions, zsh-syntax-highlighting
#   - Theme: powerlevel10k (run `p10k configure` later if desired)
#   - Disables Oh My Zsh auto-updates (new zstyle only; no legacy env vars)
#   - Idempotent: safe to re-run
# Usage    :
#   sudo -i
#   bash setup-zsh-root.sh
# Notes    :
#   - This script sets Zsh as root's default shell at the end.
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- root requirement --------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root (e.g., sudo -i then bash setup-zsh-root.sh)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
ROOT_HOME="/root"
export ZSH="${ROOT_HOME}/.oh-my-zsh"

echo ">>> Installing base packages..."
apt-get update -y
apt-get install -y zsh git curl ca-certificates

# ---- Install Oh My Zsh for root (no auto-run, no chsh here) ------------------
if [[ ! -d "${ZSH}" ]]; then
  echo ">>> Installing Oh My Zsh for root..."
  KEEP_ZSHRC=yes RUNZSH=no CHSH=no \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# ---- Install plugins ---------------------------------------------------------
ZSH_CUSTOM="${ZSH_CUSTOM:-${ZSH}/custom}"

if [[ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]]; then
  echo ">>> Installing plugin: zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi

if [[ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]]; then
  echo ">>> Installing plugin: zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
fi

# ---- Install theme: powerlevel10k -------------------------------------------
if [[ ! -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]]; then
  echo ">>> Installing theme: powerlevel10k..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k"
fi

# ---- Write a managed .zshrc (backup once if not already backed up) -----------
ZSHRC="${ROOT_HOME}/.zshrc"
if [[ -f "${ZSHRC}" && ! -f "${ZSHRC}.bak" ]]; then
  cp -a "${ZSHRC}" "${ZSHRC}.bak"
fi

cat > "${ZSHRC}" <<"EOF"
# ===== Managed Zsh config for root =====
export ZSH="${HOME}/.oh-my-zsh"

# Disable Oh My Zsh auto-updates (new-style only; no legacy vars)
zstyle ':omz:update' mode disabled

# Plugins (syntax highlighting should be last)
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

# Theme: powerlevel10k (you can run `p10k configure` later)
ZSH_THEME="powerlevel10k/powerlevel10k"

# Load Oh My Zsh
source "$ZSH/oh-my-zsh.sh"

# --- Shortcuts / aliases ---
# Esc Esc -> prepend sudo to current command line
bindkey -s '\e\e' '\C-asudo \C-e'

# git log (graph, oneline, abbrev)
alias glog='git log --graph --pretty=oneline --abbrev-commit'

# ls -al
alias ll="ls -al --show-control-chars --color"

# Load Powerlevel10k config if present
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# Make keybindings feel snappier
export KEYTIMEOUT=1
# ===== End managed block =====
EOF

chown root:root "${ZSHRC}"

# ---- Make Zsh the default shell for root ------------------------------------
if [[ "$(getent passwd root | cut -d: -f7)" != "$(command -v zsh)" ]]; then
  echo ">>> Setting Zsh as the default shell for root..."
  chsh -s "$(command -v zsh)" root
fi

echo "✅ Done. Start Zsh now with: exec zsh"
echo "Tip: If you see glyph issues, use a Nerd Font (e.g., MesloLGS NF) and then run: p10k configure"
