#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-safe-rm.sh
#
# Purpose  : Install safe-rm, write a blacklist (with optional team-specific
#            entries), and place an rm wrapper so PATH prefers safe-rm.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root.
# Features :
#   - Installs safe-rm from apt
#   - Writes /etc/safe-rm.conf with critical system paths + optional extras
#   - Creates /usr/local/bin/rm wrapper that execs /usr/bin/safe-rm
#     (bypass via /bin/rm, or set SAFE_RM_BYPASS=1 to call /bin/rm)
#   - Verifies PATH order (/usr/local/bin before /bin)
#   - Idempotent: safe to re-run
# Usage    :
#   sudo -i
#   bash setup-safe-rm.sh [--extra "/data /backup /www"] [--extra-file /path/list.txt] [-h|--help]
#   # list.txt: one absolute path per line; lines starting with # are ignored.
# -----------------------------------------------------------------------------

set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }


# ---- parse args (no functions) ----------------------------------------------
EXTRA_STR=""
EXTRA_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --extra)      shift; EXTRA_STR="${1:-}";;
    --extra-file) shift; EXTRA_FILE="${1:-}";;
    -h|--help)
      cat <<'EOF'
Usage:
  setup-safe-rm.sh [--extra "/data /backup /www"] [--extra-file /path/list.txt] [-h|--help]

Notes:
  - Only absolute paths are accepted; blank lines and comments (#...) are ignored.
  - Duplicates are removed; trailing slashes are normalized (except "/" itself).
  - To bypass wrapper temporarily: use /bin/rm, or set SAFE_RM_BYPASS=1.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift || true
done

export DEBIAN_FRONTEND=noninteractive

# ---- [1/5] Install safe-rm ---------------------------------------------------
echo ">>> [1/5] Installing safe-rm..."
apt-get update -y
apt-get install -y safe-rm
if ! command -v safe-rm >/dev/null 2>&1; then
  echo "safe-rm not found after install. Aborting." >&2
  exit 1
fi
echo "safe-rm found at: $(command -v safe-rm)"

# ---- [2/5] Build base blacklist + extras (dedup & sanitize) ------------------
echo ">>> [2/5] Building blacklist (with optional team extras)..."
TMPDIR="$(mktemp -d)"
BASE="${TMPDIR}/base.list"
EXTRA="${TMPDIR}/extra.list"
MERGED="${TMPDIR}/merged.list"

cat > "${BASE}" <<'EOF'
/
# Critical top-level system directories
/bin
/boot
/dev
/etc
/home
/lib
/lib32
/lib64
/libx32
/media
/mnt
/opt
/proc
/root
/run
/sbin
/snap
/srv
/sys
/tmp
/usr
/var
EOF

# Collect extras from --extra and --extra-file (absolute paths only)
: > "${EXTRA}"

# --extra (space-separated, may be quoted as a single string)
if [[ -n "${EXTRA_STR}" ]]; then
  # Split on whitespace
  while read -r p; do
    [[ -z "${p// }" ]] && continue
    # normalize: must start with /
    if [[ "${p}" != /* ]]; then
      echo "Skipping non-absolute path in --extra: ${p}" >&2
      continue
    fi
    # trim trailing slashes except for /
    if [[ "${p}" != "/" ]]; then
      p="${p%/}"
    fi
    printf '%s\n' "${p}" >> "${EXTRA}"
  done < <(printf '%s\n' ${EXTRA_STR})
fi

# --extra-file (one path per line)
if [[ -n "${EXTRA_FILE}" ]]; then
  if [[ ! -r "${EXTRA_FILE}" ]]; then
    echo "Extra file not readable: ${EXTRA_FILE}" >&2
    exit 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    # ignore blanks & comments
    [[ -z "${line// }" || "${line}" =~ ^# ]] && continue
    # absolute only
    if [[ "${line}" != /* ]]; then
      echo "Skipping non-absolute path in --extra-file: ${line}" >&2
      continue
    fi
    if [[ "${line}" != "/" ]]; then
      line="${line%/}"
    fi
    printf '%s\n' "${line}" >> "${EXTRA}"
  done < "${EXTRA_FILE}"
fi

# Merge & dedupe, keep base order first then extras
# - strip comments & blanks
# - uniq by full line content
awk '
  BEGIN{ OFS="\n" }
  FNR==NR{
    if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) next;
    if (!seen[$0]++) print $0;
    next
  }
  {
    if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) next;
    if (!seen[$0]++) print $0;
  }
' "${BASE}" "${EXTRA}" > "${MERGED}"

echo "Blacklist entries:"
nl -ba "${MERGED}" | sed 's/^/  /'

# ---- [3/5] Write /etc/safe-rm.conf (backup once per run) ---------------------
echo ">>> [3/5] Writing /etc/safe-rm.conf"
CONF="/etc/safe-rm.conf"
if [[ -e "$CONF" || -L "$CONF" ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  mv -v -- "$CONF" "${CONF}.bak.${TS}"
fi
{
  echo "# Managed by setup-safe-rm.sh on $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "# Base system paths + team extras (deduped). One absolute path per line."
  cat "${MERGED}"
} > "${CONF}"
chmod 0644 "${CONF}"
echo "Blacklist written: $CONF"

# ---- [4/5] Place wrapper /usr/local/bin/rm ----------------------------------
echo ">>> [4/5] Creating /usr/local/bin/rm wrapper (PATH precedence over /bin/rm)..."
WRAPPER="/usr/local/bin/rm"
mkdir -p /usr/local/bin
if [[ -e "$WRAPPER" && ! -L "$WRAPPER" ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  mv -v -- "$WRAPPER" "${WRAPPER}.bak.${TS}"
fi
install -m 0755 /dev/stdin "$WRAPPER" <<'SH'
#!/usr/bin/env bash
# Wrapper for rm -> safe-rm
# To bypass, either:
#   1) call /bin/rm explicitly, or
#   2) set SAFE_RM_BYPASS=1 in the environment.
if [[ "${SAFE_RM_BYPASS:-}" == "1" ]]; then
  exec /bin/rm "$@"
else
  exec /usr/bin/safe-rm "$@"
fi
SH
echo "Wrapper placed: $WRAPPER"

# ---- [5/5] Verify PATH order -------------------------------------------------
echo ">>> [5/5] Verifying PATH order (/usr/local/bin before /bin is preferred)..."
had_local_before_bin="no"
IFS=':' read -r -a path_order <<<"${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
for p in "${path_order[@]}"; do
  if [[ "$p" == "/usr/local/bin" ]]; then
    had_local_before_bin="yes"; break
  elif [[ "$p" == "/bin" ]]; then
    break
  fi
done

if [[ "$had_local_before_bin" != "yes" ]]; then
  echo "Warning: /usr/local/bin does not come before /bin in PATH." >&2
  cat >&2 <<'EOF'
If you want the wrapper to be used in interactive shells, create:
/etc/profile.d/00-local-path-first.sh
-----------------------------------
# Ensure /usr/local/bin is at the front of PATH
case ":$PATH:" in
  *":/usr/local/bin:"*) ;;
  *) export PATH="/usr/local/bin:$PATH" ;;
esac
EOF
fi

echo
echo "rm resolves to: $(command -v rm)"
echo "PATH: $PATH"
echo
echo "✅ Done. safe-rm is active and will block dangerous deletions (e.g., rm -rf /*)."
echo "To temporarily bypass, use: /bin/rm <args>  or  SAFE_RM_BYPASS=1 rm <args>"
echo
echo "Quick safety checks (should be refused by safe-rm):"
echo "  rm -rf /usr"
echo "  rm -rf /etc"

# Cleanup
rm -rf "${TMPDIR}"
