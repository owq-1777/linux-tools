linux-tools
===========

Lean ops/dev tooling for fast workstation bootstrap and local service containers.

Docker stacks
-------------
- MariaDB: `docker compose -f docker/mariadb/docker-compose.yaml up -d`
- Redis: `docker compose -f docker/redis/docker-compose.yaml up -d`
- Logs: e.g. `docker compose -f docker/mariadb/docker-compose.yaml logs -f mariadb`
- Stop a stack with the same compose file and `down`

Script catalog
--------------

All scripts live in `scripts/`. Run them with `bash scripts/<name>.sh`. Root-oriented scripts expect `sudo -i` first.

Supported Ubuntu Versions
-------------------------
- Ubuntu 22.04 (Jammy)
- Ubuntu 24.04 (Noble)
- PHP uses an availability-based fallback (8.4 → 8.3 → 8.2) on 24.04.

Control script
--------------
- `control.sh` – bilingual interactive orchestrator at repo root
  - Discover and run any scripts under `scripts/`
  - Recommended order runner with visual progress (system base → toolchain → zsh → safe-rm → ssh → docker → user dev tools)

- `install-docker.sh` – install Docker Engine + compose plugin via Docker apt repo
- `install-nginx.sh` – build nginx 1.28.0 with headers-more, stealth defaults, custom conf
- `install-php.sh` – install PHP (default 8.4) + FPM + common extensions via ondrej/php PPA
- `setup-system-build-toolchain.sh` – install compilers, CMake, Ninja, Python build deps
- `setup-system-base.sh` – add baseline build deps plus Go toolchain, and system Vim/tmux defaults
  - consolidated: editors and tmux defaults are provided by system base
- `setup-system-zsh-root.sh` – install Zsh, Oh My Zsh, plugins, Powerlevel10k for root
- `setup-user-create-dev-from-root-zsh.sh` – create `dev` user, mirror root Zsh profile, add docker/sudo
- `setup-system-ssh-defaults.sh --target-user <name>` – provision ~/.ssh, ed25519 keypair, authorized_keys
- `setup-system-safe-rm.sh` – install safe-rm wrapper with default deny list
- `setup-user-dev-tools.sh` – install per-user dev stack (nvm, Node LTS, pnpm, rustup, uv)

Safety notes
------------
- Review passwords, bind mounts, and exposed ports before sharing docker configs
- Scripts aim to be idempotent but confirm destructive steps on important hosts first

Control script visual flow
--------------------------
- Requires `whiptail` or `dialog` for graphical menus (falls back to text mode if missing)
- Shows step-by-step progress with a gauge, logs stored under `.logs/`
- On errors, review the corresponding log file and rerun the step via the control script
