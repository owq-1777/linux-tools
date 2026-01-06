#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-system-base.sh
#
# Purpose  : Install system-wide build deps、Go（可选）并集成 Vim/tmux 系统级默认配置。
# OS       : Ubuntu 22.04 (Jammy) / 24.04 (Noble) - 64-bit
# User     : Must be run as root.
# Features :
#   - Installs build-essential, pkg-config, git, curl, ca-certificates, unzip, xz-utils, tar
#   - Installs Go under /usr/local/go (idempotent; existing moved to .bak.<ts>)
#   - Adds /usr/local/go/bin to system PATH via /etc/profile.d
#   - Prints versions for verification
# Usage    :
#   sudo -i
#   bash setup-system-base.sh
# Notes    :
#   - Adjust GO_VERSION if needed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/os.sh"
require_supported_ubuntu
ensure_apt_ready

[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }

export DEBIAN_FRONTEND=noninteractive
GO_VERSION="1.25.4"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"

echo ">>> Installing base packages..."
apt-get update -y
filter_available() {
  local out=()
  for pkg in "$@"; do
    if apt-cache policy "$pkg" 2>/dev/null | awk -F': ' '/Candidate:/ {print $2}' | grep -qv '(none)'; then
      out+=("$pkg")
    fi
  done
  printf '%s\n' "${out[@]}"
}
pkgs=(build-essential pkg-config git curl ca-certificates unzip xz-utils tar vim tmux)
mapfile -t avail_pkgs < <(filter_available "${pkgs[@]}")
apt-get install -y "${avail_pkgs[@]}"

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

# --- System-wide Vim defaults ---
echo ">>> Configuring system-wide Vim defaults..."
VIM_LOCAL="/etc/vim/vimrc.local"
MARK_BEGIN_VIM='" BEGIN managed system vim defaults'
MARK_END_VIM='" END managed system vim defaults'
mkdir -p /etc/vim || true
touch "${VIM_LOCAL}"
awk -v b="$MARK_BEGIN_VIM" -v e="$MARK_END_VIM" '
  BEGIN{inblk=0}
  $0~b{inblk=1;next}
  $0~e{inblk=0;next}
  !inblk{print}
' "${VIM_LOCAL}" > "${VIM_LOCAL}.tmp"
cat >> "${VIM_LOCAL}.tmp" <<'EOF'
" BEGIN managed system vim defaults
" 基础设置 ---------------------------------------------------------
set nocompatible          " 关闭 vi 兼容模式
set encoding=utf-8
set fileencoding=utf-8
set termencoding=utf-8

set number                " 显示行号
set ruler                 " 右下角显示光标位置
set showcmd               " 右下角显示命令
set showmode              " 显示当前模式

set mouse=a               " 开启鼠标（终端里也可选中滚动）
set clipboard=unnamedplus " 使用系统剪贴板（需要 Vim 编译支持）

" 外观 -------------------------------------------------------------
syntax on                 " 语法高亮
colorscheme desert
set t_Co=256
set termguicolors         " 终端支持真彩就开
set cursorline            " 高亮当前行
set showmatch             " 括号匹配高亮
set scrolloff=5           " 上下保留若干行
set laststatus=2          " 总是显示状态栏
set wildmenu              " 命令行补全增强
set wildmode=longest:full,full

" 搜索 -------------------------------------------------------------
set ignorecase            " 搜索忽略大小写
set smartcase             " 有大写字母时恢复大小写敏感
set incsearch             " 输入时实时高亮匹配
set hlsearch              " 高亮搜索结果

" 缩进 / Tab -------------------------------------------------------
set smartindent           " 简单智能缩进
set autoindent
set expandtab             " 用空格代替 Tab
set tabstop=4             " 一个 Tab 显示为 4 列
set shiftwidth=4          " >> << 每次移动 4 列
set softtabstop=4         " 插入模式下退格一次删 4 个空格
set smarttab

" 编码与换行 -------------------------------------------------------
set fileformats=unix,dos,mac
set nowrap                " 不自动换行
set linebreak             " 如需换行，以词为单位
set backspace=indent,eol,start

" 文件 / 备份 ------------------------------------------------------
set nobackup
set nowritebackup
set noswapfile

" 持久化 undo（建议手动建目录：mkdir -p ~/.vim/undo）
if has('persistent_undo')
    set undofile
    set undodir=~/.vim/undo
endif

" 性能 / 兼容 ------------------------------------------------------
set hidden                " 允许缓冲区在后台隐藏
set updatetime=300        " 触发 CursorHold 等事件的时间
set ttyfast               " 更快的重绘（老说法，但无害）
set shortmess+=c          " 补全时少说废话

" 键位映射 ---------------------------------------------------------
let mapleader=" "         " 空格做 Leader 键

" 快捷保存/退出
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>x :x<CR>

" 清除搜索高亮
nnoremap <leader><space> :nohlsearch<CR>

" 分屏移动：Ctrl + h/j/k/l
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" 更自然的上下移动（对长行换行时）
nnoremap j gj
nnoremap k gk

" 快速切换上一/下一个 buffer
nnoremap <leader>bn :bnext<CR>
nnoremap <leader>bp :bprevious<CR>

" 插入模式下快速退出到普通模式
inoremap jk <Esc>
inoremap kj <Esc>

" 实用小功能 -------------------------------------------------------
" 自动去掉多余空格（保存前）
autocmd BufWritePre * :%s/\s\+$//e

" 不同文件类型的特定缩进
augroup filetype_indent
    autocmd!
    " Python 2 空格缩进
    autocmd FileType python setlocal tabstop=4 shiftwidth=4 expandtab
    " Web 前端 2 空格缩进
    autocmd FileType html,css,javascript,typescript setlocal tabstop=2 shiftwidth=2 expandtab
augroup END

set pastetoggle=<F2>   " 插入模式里按 F2 自动切换 paste 模式
" END managed system vim defaults
EOF
mv "${VIM_LOCAL}.tmp" "${VIM_LOCAL}"
vim --version | head -n1 || true

# --- System-wide tmux defaults ---
echo ">>> Configuring system-wide tmux defaults..."
TMUX_CONF_DIR="/etc/tmux"
TMUX_CONF="${TMUX_CONF_DIR}/tmux.conf"
MARK_BEGIN_TMUX="# BEGIN managed system tmux defaults"
MARK_END_TMUX="# END managed system tmux defaults"
mkdir -p "${TMUX_CONF_DIR}"
touch "${TMUX_CONF}"
awk -v b="$MARK_BEGIN_TMUX" -v e="$MARK_END_TMUX" '
  BEGIN{inblk=0}
  $0~b{inblk=1;next}
  $0~e{inblk=0;next}
  !inblk{print}
' "${TMUX_CONF}" > "${TMUX_CONF}.tmp"
cat >> "${TMUX_CONF}.tmp" <<'EOF'
# BEGIN managed system tmux defaults
set -g default-terminal "screen-256color"
set -g status-interval 5
set -g status-keys vi
set -g mouse on
set -g history-limit 100000
set -g prefix C-a
unbind C-b
bind C-a send-prefix
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind -r C-h select-window -t :-
bind -r C-l select-window -t :+
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-selection
bind -T copy-mode-vi r send -X rectangle-toggle
# END managed system tmux defaults
EOF
mv "${TMUX_CONF}.tmp" "${TMUX_CONF}"
tmux -V || true

echo "✅ System base + Vim/tmux 默认配置就绪。"
