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

All scripts sit in `scripts/`. Run them with `bash scripts/<name>.sh`. Root-oriented scripts expect `sudo -i` first.

- `install-docker-root.sh` – install Docker Engine + compose plugin system-wide
- `setup-build-toolchain.sh` – install compilers, CMake, Ninja, Python build deps
- `setup-system-build-deps.sh` – install general build deps and Go toolchain
- `setup-zsh-root.sh` – install Zsh, Oh My Zsh, plugins, Powerlevel10k for root
- `create-dev-from-root-zsh.sh` – create `dev` user, mirror root Zsh config, add docker/sudo groups
- `setup-ssh-defaults.sh --target-user <name>` – provision ~/.ssh and generate ed25519 keypair
- `setup-safe-rm.sh` – install safe-rm wrapper with default blacklist
- `setup-php84-fpm.sh` – configure PHP 8.4 FPM and common extensions
- `setup-dev-tools-user.sh` – install per-user dev tools (nvm, Node LTS, pnpm, rustup, uv)
- `build-nginx-stable-stealth.sh` – build nginx with stealth modules (requires toolchain deps)

Safety notes
------------
- Review passwords, bind mounts, and exposed ports before sharing docker configs
- Scripts aim to be idempotent but confirm destructive steps on important hosts first
