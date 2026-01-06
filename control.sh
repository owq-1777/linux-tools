#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/.logs"
mkdir -p "${LOG_DIR}"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
REPO_OWNER="owq-1777"
REPO_NAME="linux-tools"
REF="main"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/linux-tools/${REF}/scripts"
REMOTE_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REF}"
REMOTE_SCRIPTS=(
  setup-system-base.sh
  setup-system-build-toolchain.sh
  setup-system-zsh-root.sh
  setup-system-safe-rm.sh
  setup-system-ssh-defaults.sh
  install-docker.sh
  setup-user-dev-tools.sh
  setup-user-create-dev-from-root-zsh.sh
  install-nginx.sh
  install-php.sh
)

LANG_CHOICE=""
HAS_WHIPTAIL=""
HAS_DIALOG=""

msg() {
  local key="$1"; shift || true
  case "${LANG_CHOICE:-auto}" in
    zh|auto)
      case "$key" in
        title) echo "系统安装与配置控制脚本";;
        choose_lang) echo "选择语言: [1] 中文  [2] English";;
        main_menu) echo "主菜单:";;
        opt_run_scripts) echo "运行 scripts 目录下的脚本";;
        opt_install_docker) echo "安装 Docker";;
        opt_config_docker_root) echo "配置 Docker 数据目录到 /docker";;
        opt_manage_stacks) echo "管理 Compose 栈 (复制到 /docker/stacks)";;
        opt_switch_lang) echo "切换语言";;
        opt_exit) echo "退出";;
        enter_choice) echo "请输入编号:";;
        need_root) echo "需要以 root 运行此操作。将使用 sudo 执行。";;
        confirm) echo "确认执行? [y/N]";;
        done) echo "完成";;
        error) echo "发生错误";;
        list_scripts) echo "远程脚本列表 (按编号选择执行，支持逗号分隔):";;
        downloading) echo "正在下载脚本...";;
        cache_hit) echo "命中缓存，跳过下载";;
        download_failed) echo "下载失败";;
        no_scripts) echo "未在 scripts 目录发现脚本";;
        invalid_choice) echo "无效的选择";;
        docker_not_installed) echo "未检测到 Docker，请先安装。";;
        will_config_root) echo "将把 Docker 数据目录迁移到 /docker，需停机并复制数据。";;
        docker_config_done) echo "Docker 数据目录已配置为 /docker";;
        *) echo "$key";;
      esac
      ;;
    en)
      case "$key" in
        title) echo "System Setup & Configuration Control";;
        choose_lang) echo "Choose language: [1] 中文  [2] English";;
        main_menu) echo "Main Menu:";;
        opt_run_scripts) echo "Run scripts under 'scripts'";;
        opt_install_docker) echo "Install Docker";;
        opt_config_docker_root) echo "Configure Docker data-root to /docker";;
        opt_manage_stacks) echo "Manage Compose stacks (copy to /docker/stacks)";;
        opt_switch_lang) echo "Switch language";;
        opt_exit) echo "Exit";;
        enter_choice) echo "Enter number:";;
        need_root) echo "Root privileges required. Will use sudo.";;
        confirm) echo "Proceed? [y/N]";;
        done) echo "Done";;
        error) echo "Error occurred";;
        list_scripts) echo "Remote scripts (choose numbers, comma-separated supported):";;
        downloading) echo "Downloading script...";;
        cache_hit) echo "Cache hit, skip download";;
        download_failed) echo "Download failed";;
        no_scripts) echo "No scripts found in 'scripts' directory";;
        invalid_choice) echo "Invalid choice";;
        docker_not_installed) echo "Docker not detected, please install first.";;
        will_config_root) echo "Docker data-root will be migrated to /docker; service stop and copy required.";;
        docker_config_done) echo "Docker data-root configured to /docker";;
        *) echo "$key";;
      esac
      ;;
  esac
}

choose_language() {
  echo "$(msg choose_lang)"
  read -r sel
  case "$sel" in
    1) LANG_CHOICE="zh";;
    2) LANG_CHOICE="en";;
    *) LANG_CHOICE="zh";;
  esac
}

detect_ui() {
  if command -v whiptail >/dev/null 2>&1; then
    HAS_WHIPTAIL=1
  elif command -v dialog >/dev/null 2>&1; then
    HAS_DIALOG=1
  else
    HAS_WHIPTAIL=""
    HAS_DIALOG=""
  fi
}

ui_menu() {
  local title; title="$(msg title)"
  if [[ -n "$HAS_WHIPTAIL" ]]; then
    whiptail --title "$title" --menu "$(msg main_menu)" 20 78 10 \
      "1" "$(msg opt_run_scripts)" \
      "2" "推荐执行顺序 / Recommended order" \
      "3" "Ubuntu 24 端到端测试" \
      "4" "运行远程脚本" \
      "5" "$(msg opt_switch_lang)" \
      "9" "$(msg opt_exit)" \
      3>&1 1>&2 2>&3
    return $?
  elif [[ -n "$HAS_DIALOG" ]]; then
    dialog --title "$title" --menu "$(msg main_menu)" 20 78 10 \
      1 "$(msg opt_run_scripts)" \
      2 "推荐执行顺序 / Recommended order" \
      3 "Ubuntu 24 端到端测试" \
      4 "运行远程脚本" \
      5 "$(msg opt_switch_lang)" \
      9 "$(msg opt_exit)" \
      3>&1 1>&2 2>&3
    return $?
  else
    echo "[1] $(msg opt_run_scripts)"
    echo "[2] 推荐执行顺序 / Recommended order"
    echo "[3] Ubuntu 24 端到端测试"
    echo "[4] 运行远程脚本"
    echo "[5] $(msg opt_switch_lang)"
    echo "[9] $(msg opt_exit)"
    echo "$(msg enter_choice)"
    read -r choice
    echo "$choice"
    return 0
  fi
}

list_local_scripts() {
  find "${SCRIPTS_DIR}" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ref)
        REF="${2:-main}"; shift 2 ;;
      *) shift ;;
    esac
  done
  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/linux-tools/${REF}/scripts"
  REMOTE_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REF}"
}

ensure_downloader() {
  command -v curl >/dev/null 2>&1 && return 0
  command -v wget >/dev/null 2>&1 && return 0
  echo "curl or wget required"
  exit 1
}

fetch_script() {
  local name="$1"
  mkdir -p "${CACHE_DIR}"
  local dst="${CACHE_DIR}/${name}"
  if [[ -s "$dst" ]]; then
    echo "$(msg cache_hit)" >/dev/null
    chmod +x "$dst" || true
    echo "$dst"
    return 0
  fi
  ensure_downloader
  local url="${REMOTE_BASE}/scripts/${name}"
  echo "$(msg downloading)" >/dev/null
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dst" || { echo "$(msg download_failed)"; return 1; }
  else
    wget -qO "$dst" "$url" || { echo "$(msg download_failed)"; return 1; }
  fi
  chmod +x "$dst" || true
  echo "$dst"
}

need_root_or_sudo() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "$(msg need_root)"
    echo "sudo -v" >/dev/null 2>&1 || true
  fi
}

run_remote_script() {
  local name="$1"; shift || true
  local args="$*"
  local path
  path="$(fetch_script "$name")" || return 1
  if grep -q "Must be run as root" "$path" 2>/dev/null; then
    need_root_or_sudo
    sudo bash "$path" $args
  else
    bash "$path" $args
  fi
}

run_local_script() {
  local path="$1"; shift || true
  local args="$*"
  local need_root=""
  if grep -Eiq 'Must be run as root|Please run as root' "$path" 2>/dev/null; then
    need_root=1
  fi
  local base; base="$(basename "$path")"
  mkdir -p "${LOG_DIR}"
  if [[ -n "$need_root" ]]; then
    need_root_or_sudo
    sudo bash "$path" $args >"${LOG_DIR}/${base}.log" 2>&1
  else
    bash "$path" $args >"${LOG_DIR}/${base}.log" 2>&1
  fi
  tail -n 5 "${LOG_DIR}/${base}.log" 2>/dev/null || true
}

install_docker() {
  run_remote_script "install-docker.sh"
}

configure_docker_root() {
  echo "$(msg will_config_root)"
  echo "$(msg confirm)"
  read -r ans
  case "${ans:-N}" in
    y|Y)
      need_root_or_sudo
      local ts; ts="$(date +%Y%m%d-%H%M%S)"
      sudo mkdir -p /docker
      sudo chown root:docker /docker || true
      sudo chmod 0755 /docker
      sudo systemctl stop docker.socket || true
      sudo systemctl stop docker || true
      if [[ -d /var/lib/docker ]]; then
        sudo rsync -aHAX /var/lib/docker/ /docker/ || true
        sudo mv /var/lib/docker "/var/lib/docker.bak.${ts}" || true
      fi
      sudo mkdir -p /etc/docker
      if command -v jq >/dev/null 2>&1; then
        if [[ -f /etc/docker/daemon.json ]]; then
          sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.${ts}"
          sudo sh -c 'jq ".\"data-root\"=\"/docker\"" /etc/docker/daemon.json > /etc/docker/daemon.json.tmp && mv /etc/docker/daemon.json.tmp /etc/docker/daemon.json'
        else
          echo '{"data-root":"/docker"}' | sudo tee /etc/docker/daemon.json >/dev/null
        fi
      else
        if [[ -f /etc/docker/daemon.json ]]; then
          sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.${ts}"
          sudo sed -i 's/"data-root"[[:space:]]*:[[:space:]]*"[^"]*"/"data-root":"\/docker"/g' /etc/docker/daemon.json || true
          grep -q '"data-root"' /etc/docker/daemon.json || echo '{"data-root":"/docker"}' | sudo tee /etc/docker/daemon.json >/dev/null
        else
          echo '{"data-root":"/docker"}' | sudo tee /etc/docker/daemon.json >/dev/null
        fi
      fi
      sudo systemctl daemon-reload || true
      sudo systemctl start docker || true
      docker info 2>/dev/null | grep -q "Docker Root Dir: /docker" && echo "$(msg docker_config_done)" || echo "$(msg error)"
      ;;
    *) ;;
  esac
}

manage_stacks() {
  local stacks_src="${SCRIPT_DIR}/docker"
  local stacks_dst="/docker/stacks"
  need_root_or_sudo
  sudo mkdir -p "$stacks_dst"
  if [[ -d "$stacks_src" ]]; then
    for d in "$stacks_src"/*; do
      [[ -d "$d" ]] || continue
      sudo rsync -a "$d" "$stacks_dst/"
    done
    echo "Stacks synced to $stacks_dst"
  else
    echo "No local docker stacks at $stacks_src"
  fi
}

run_scripts_menu() {
  local list; list=("${REMOTE_SCRIPTS[@]}")
  echo "$(msg list_scripts)"
  local i=1
  for s in "${list[@]}"; do
    echo "[$i] $s"
    i=$((i+1))
  done
  echo "$(msg enter_choice)"
  read -r choices
  IFS=',' read -ra idxs <<< "$choices"
  for idx in "${idxs[@]}"; do
    [[ "$idx" =~ ^[0-9]+$ ]] || { echo "$(msg invalid_choice)"; continue; }
    local pos=$((idx))
    if (( pos>=1 && pos<=${#list[@]} )); then
      local sel="${list[$((pos-1))]}"
      run_remote_script "$sel" || echo "$(msg error): $sel"
    else
      echo "$(msg invalid_choice)"
    fi
  done
}

run_local_menu() {
  local items; mapfile -t items < <(list_local_scripts)
  if ((${#items[@]}==0)); then
    echo "$(msg no_scripts)"
    return 0
  fi
  if [[ -n "$HAS_WHIPTAIL" || -n "$HAS_DIALOG" ]]; then
    local pairs=(); local i=1
    for s in "${items[@]}"; do
      pairs+=("$i" "$s" OFF)
      i=$((i+1))
    done
    local sel
    if [[ -n "$HAS_WHIPTAIL" ]]; then
      sel="$(whiptail --title "$(msg list_scripts)" --checklist "$(msg list_scripts)" 25 90 15 "${pairs[@]}" 3>&1 1>&2 2>&3)" || return 0
    else
      sel="$(dialog --title "$(msg list_scripts)" --checklist "$(msg list_scripts)" 25 90 15 "${pairs[@]}" 3>&1 1>&2 2>&3)" || return 0
    fi
    for idx in $sel; do
      idx="${idx//\"/}"
      if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx>=1 && idx<=${#items[@]} )); then
        run_local_script "${SCRIPTS_DIR}/${items[$((idx-1))]}"
      fi
    done
  else
    local i=1
    for s in "${items[@]}"; do
      echo "[$i] $s"
      i=$((i+1))
    done
    echo "$(msg enter_choice)"
    read -r choices
    IFS=',' read -ra idxs <<< "$choices"
    for idx in "${idxs[@]}"; do
      [[ "$idx" =~ ^[0-9]+$ ]] || { echo "$(msg invalid_choice)"; continue; }
      local pos=$((idx))
      if (( pos>=1 && pos<=${#items[@]} )); then
        run_local_script "${SCRIPTS_DIR}/${items[$((pos-1))]}"
      else
        echo "$(msg invalid_choice)"
      fi
    done
  fi
}

recommended_order() {
  local steps=(
    "Base|setup-system-base.sh||root|vim --version | head -n1"
    "Toolchain|setup-system-build-toolchain.sh||root|cmake --version | head -n1"
    "Zsh(root)|setup-system-zsh-root.sh||root|zsh --version | head -n1"
    "Safe rm|setup-system-safe-rm.sh||root|safe-rm --version 2>/dev/null || echo safe-rm installed"
    "SSH defaults|setup-system-ssh-defaults.sh|--target-user ${TARGET_USER:-}|root|true"
    "Docker|install-docker.sh||root|docker --version"
    "User dev tools|setup-user-dev-tools.sh||user|node -v || true"
  )
  local total=${#steps[@]}
  local idx=0
  for meta in "${steps[@]}"; do
    idx=$((idx+1))
    local name script args run_as post
    name="$(echo "$meta" | cut -d'|' -f1)"
    script="$(echo "$meta" | cut -d'|' -f2)"
    args="$(echo "$meta" | cut -d'|' -f3)"
    run_as="$(echo "$meta" | cut -d'|' -f4)"
    post="$(echo "$meta" | cut -d'|' -f5)"
    local pct=$((idx*100/total))
    if [[ -n "$HAS_WHIPTAIL" ]]; then
      whiptail --gauge "${name}" 6 60 $pct < /dev/null || true
    elif [[ -n "$HAS_DIALOG" ]]; then
      dialog --gauge "${name}" 6 60 $pct < /dev/null || true
    else
      echo "▶ ${name} (${idx}/${total})"
    fi
    local fetched; fetched="$(fetch_script "$script")" || { echo "✖ ${name}"; continue; }
    if [[ "$run_as" == "root" ]]; then
      need_root_or_sudo
      sudo bash "$fetched" $args >"${LOG_DIR}/${script}.log" 2>&1 || { echo "✖ ${name}"; continue; }
    else
      bash "$fetched" $args >"${LOG_DIR}/${script}.log" 2>&1 || { echo "✖ ${name}"; continue; }
    fi
    bash -c "$post" >/dev/null 2>&1 || true
    echo "✔ ${name}"
  done
}

main_menu() {
  while true; do
    detect_ui
    local choice
    choice="$(ui_menu)"
    case "$choice" in
      1) run_local_menu ;;
      2) recommended_order ;;
      3) bash "${SCRIPT_DIR}/tests/e2e-ubuntu-24.sh" || true ;;
      4) run_scripts_menu ;;
      5) choose_language ;;
      9) break ;;
      *) echo "$(msg invalid_choice)" ;;
    esac
  done
}

parse_args "$@"
choose_language
TARGET_USER=""
echo "Target user (for SSH defaults & user tools), blank to skip:"; read -r TARGET_USER || true
main_menu
echo "$(msg done)"
