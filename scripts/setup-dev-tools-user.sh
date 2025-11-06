#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-dev-tools-user.sh
#
# Purpose  : Install per-user dev tools: uv, Node.js (via nvm) + pnpm, and Rust (rustup).
# OS       : Ubuntu 22.04 (Jammy) - 64-bit (and most modern Linux)
# User     : Run as a normal user (not root). Installs into $HOME.
# Features :
#   - Installs uv to ~/.local/bin
#   - Installs nvm, Node.js LTS, enables Corepack, activates pnpm
#   - Installs rustup (rustc/cargo) under ~/.cargo
#   - Manages PATH block in ~/.profile and ~/.zshrc (idempotent)
#   - Prints versions for verification
# Usage    :
#   bash setup-dev-tools-user.sh
# Notes    :
#   - Requires network access.
#   - If you already have these tools, the script will reuse/verify them.
# -----------------------------------------------------------------------------

set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Warning: This script is intended for a regular user, not root." >&2
fi

# --- constants / markers ---
NVM_VERSION="v0.39.7"
MARK_BEGIN="# BEGIN dev-tools PATH"
MARK_END="# END dev-tools PATH"

# --- ensure ~/.local/bin exists early ---
mkdir -p "${HOME}/.local/bin"

# --- install uv (per-user) ---
echo ">>> Installing uv..."
curl -fsSL https://astral.sh/uv/install.sh | sh
# uv typically installs to ~/.local/bin/uv

# --- install nvm (do not let installer touch profiles; we manage our own) ---
echo ">>> Installing nvm ${NVM_VERSION}..."
export PROFILE=/dev/null
if [[ ! -d "${HOME}/.nvm" ]]; then
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi
export NVM_DIR="${HOME}/.nvm"
# shellcheck disable=SC1091
[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"

echo ">>> Installing Node.js LTS and enabling Corepack/pnpm..."
nvm install --lts
nvm alias default 'lts/*'
# Corepack provides pnpm; prepare latest and activate
corepack enable
corepack prepare pnpm@latest --activate

# --- install rustup (non-interactive) ---
echo ">>> Installing Rust toolchain via rustup..."
if [[ ! -x "${HOME}/.cargo/bin/rustup" ]]; then
  curl -fsSL https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1091
[ -f "${HOME}/.cargo/env" ] && . "${HOME}/.cargo/env"

# --- managed PATH block (profile + zshrc), idempotent replace ---
write_block() {
  local file="$1"
  touch "$file"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    BEGIN{inblk=0}
    $0~b{inblk=1;next}
    $0~e{inblk=0;next}
    !inblk{print}
  ' "$file" > "${file}.tmp"
  cat >> "${file}.tmp" <<'EOF'
# BEGIN dev-tools PATH
# Make sure per-user tool directories are on PATH.
[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
# nvm (only load in interactive shells that need it)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
# If Go was installed system-wide, prefer it as well
[ -d "/usr/local/go/bin" ] && case ":$PATH:" in *":/usr/local/go/bin:"*) ;; *) export PATH="/usr/local/go/bin:$PATH" ;; esac
# END dev-tools PATH
EOF
  mv "${file}.tmp" "$file"
}

echo ">>> Updating PATH blocks in ~/.profile and ~/.zshrc ..."
write_block "${HOME}/.profile"
write_block "${HOME}/.zshrc"

# --- refresh current shell env for versions ---
# shellcheck disable=SC1091
[ -f "${HOME}/.profile" ] && . "${HOME}/.profile" || true
[ -f "${HOME}/.zshrc" ] && . "${HOME}/.zshrc" || true

# --- Versions (verification) ---
echo ">>> Versions:"
command -v uv >/dev/null 2>&1 && uv --version || echo "uv not found"
command -v node >/dev/null 2>&1 && node -v || echo "node not found"
command -v npm  >/dev/null 2>&1 && npm -v  || echo "npm not found"
command -v pnpm >/dev/null 2>&1 && pnpm -v || echo "pnpm not found"
command -v rustc >/dev/null 2>&1 && rustc --version || echo "rustc not found"
command -v cargo >/dev/null 2>&1 && cargo --version || echo "cargo not found"
command -v go    >/dev/null 2>&1 && go version || echo "go not found (install system-wide via setup-system-build-deps.sh)"

echo "✅ User dev tools ready."
