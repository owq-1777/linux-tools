#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-dev-tools-user.sh
#
# Purpose  : Install per-user dev tools: uv, Node.js (via nvm) + pnpm (Corepack),
#            and Rust (rustup), and manage PATH blocks idempotently.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit (and most modern Linux)
# User     : Run as a normal user (not root). Installs into $HOME.
# Features :
#   - Installs uv to ~/.local/bin
#   - Installs nvm, Node.js LTS, enables Corepack, activates pnpm
#   - Installs rustup (rustc/cargo) under ~/.cargo
#   - Writes a managed PATH block into ~/.profile and ~/.zshrc (no duplicates)
#   - Prints versions without sourcing ~/.zshrc
# Usage    :
#   bash setup-dev-tools-user.sh
# Notes    :
#   - This script does NOT source ~/.zshrc. It only sources uv/cargo/nvm env files when needed.
# -----------------------------------------------------------------------------

set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Warning: This script is intended for a regular user, not root." >&2
fi


# ---- settings ----------------------------------------------------------------
NVM_VERSION="v0.39.7"
MARK_BEGIN="# BEGIN dev-tools PATH"
MARK_END="# END dev-tools PATH"

# ---- ensure ~/.local/bin exists early ----------------------------------------
mkdir -p "${HOME}/.local/bin"

# ---- uv ----------------------------------------------------------------------
echo ">>> Installing uv..."
curl -fsSL https://astral.sh/uv/install.sh | sh
# uv typically installs to ~/.local/bin and provides ~/.local/bin/env for session env

# ---- nvm + Node LTS + Corepack/pnpm ------------------------------------------
echo ">>> Installing nvm ${NVM_VERSION}..."
# prevent installer from editing profiles; we manage our own block
export PROFILE=/dev/null
if [[ ! -d "${HOME}/.nvm" ]]; then
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi

# load nvm for THIS session (safe in bash/zsh)
export NVM_DIR="${HOME}/.nvm"
[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"

echo ">>> Installing Node.js LTS and enabling Corepack/pnpm..."
nvm install --lts
nvm alias default 'lts/*'

# Corepack comes with Node (recent LTS); enable it. Fallback to npm -g if needed.
corepack enable || { npm install -g corepack && corepack enable; }
corepack prepare pnpm@latest --activate

# ---- Rust (rustup) -----------------------------------------------------------
echo ">>> Installing Rust toolchain via rustup..."
if [[ ! -x "${HOME}/.cargo/bin/rustup" ]]; then
  curl -fsSL https://sh.rustup.rs | sh -s -- -y
fi
# for THIS session
[ -f "${HOME}/.cargo/env" ] && . "${HOME}/.cargo/env"

# ---- Managed PATH block (in ~/.profile and ~/.zshrc) -------------------------
for file in "${HOME}/.profile" "${HOME}/.zshrc"; do
  touch "${file}"
  # strip previous managed block
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    BEGIN{inblk=0}
    $0~b{inblk=1;next}
    $0~e{inblk=0;next}
    !inblk{print}
  ' "${file}" > "${file}.tmp"

  # append fresh managed block
  cat >> "${file}.tmp" <<'EOF'
# BEGIN dev-tools PATH
# per-user bin
[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
# Go (system-wide) if present
[ -d "/usr/local/go/bin" ] && case ":$PATH:" in *":/usr/local/go/bin:"*) ;; *) export PATH="/usr/local/go/bin:$PATH" ;; esac
# END dev-tools PATH
EOF

  # zsh-only: enable uv completion if available
  if [[ "${file}" == "${HOME}/.zshrc" ]]; then
    cat >> "${file}" <<'EOF'
# BEGIN uv completion (zsh)
command -v uv >/dev/null 2>&1 && eval "$(uv generate-shell-completion zsh)"
# END uv completion (zsh)
EOF
  fi

  mv "${file}.tmp" "${file}"
done

# ---- Refresh THIS session minimally (no ~/.zshrc sourcing) -------------------
[ -s "${HOME}/.local/bin/env" ] && . "${HOME}/.local/bin/env" || true
[ -s "${HOME}/.cargo/env" ] && . "${HOME}/.cargo/env" || true
# nvm was already loaded above for this session

# ---- Versions (verification) -------------------------------------------------
echo ">>> Versions:"
command -v uv    >/dev/null 2>&1 && uv --version          || echo "uv not found"
command -v node  >/dev/null 2>&1 && node -v               || echo "node not found"
command -v npm   >/dev/null 2>&1 && npm -v                || echo "npm not found"
command -v pnpm  >/dev/null 2>&1 && pnpm -v               || echo "pnpm not found"
command -v rustc >/dev/null 2>&1 && rustc --version       || echo "rustc not found"
command -v cargo >/dev/null 2>&1 && cargo --version       || echo "cargo not found"
command -v go    >/dev/null 2>&1 && go version            || echo "go not found (optional)"

echo
echo "✅ User dev tools ready."
echo "Tip: open a new terminal (or \". ~/.profile\") so new sessions pick up the PATH block."
