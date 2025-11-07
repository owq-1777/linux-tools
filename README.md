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

- `install-docker.sh` – install Docker Engine + compose plugin via Docker apt repo
- `install-nginx.sh` – build nginx 1.28.0 with headers-more, stealth defaults, custom conf
- `install-php.sh` – install PHP (default 8.4) + FPM + common extensions via ondrej/php PPA
- `setup-build-toolchain.sh` – install compilers, CMake, Ninja, Python build deps
- `setup-system-build-deps.sh` – add baseline build deps plus Go toolchain
- `setup-zsh-root.sh` – install Zsh, Oh My Zsh, plugins, Powerlevel10k for root
- `create-dev-from-root-zsh.sh` – create `dev` user, mirror root Zsh profile, add docker/sudo
- `setup-ssh-defaults.sh --target-user <name>` – provision ~/.ssh, ed25519 keypair, authorized_keys
- `setup-safe-rm.sh` – install safe-rm wrapper with default deny list
- `setup-dev-tools-user.sh` – install per-user dev stack (nvm, Node LTS, pnpm, rustup, uv)

Safety notes
------------
- Review passwords, bind mounts, and exposed ports before sharing docker configs
- Scripts aim to be idempotent but confirm destructive steps on important hosts first
