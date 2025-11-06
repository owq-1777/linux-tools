linux-tools
===========

Small ops/dev helper repository with local Docker stacks and setup scripts.

Useful commands
---------------
- Start all configured docker stacks from repo root (if using compose v2 and service directories):

```bash
cd docker/mariadb && docker compose up -d
cd docker/redis && docker compose up -d
```

- Inspect container logs:

```bash
docker compose -f docker/mariadb/docker-compose.yaml logs -f mariadb
```

Notes
-----

This repository provides convenience configs for local development. Review and adjust security-sensitive values (passwords, bind mounts, network exposure) before using in production.

Scripts quick-start
-------------------

Run these scripts from the repository root. Most root scripts require `sudo -i` (or running as root) and are idempotent.

- scripts/root/install-docker-root.sh
  - Purpose: install Docker Engine (CE) and compose plugin system-wide.
  - Quick run:

  ```bash
  sudo -i && bash scripts/root/install-docker-root.sh
  ```

- scripts/root/setup-build-toolchain.sh
  - Purpose: install compilers, C/C++ build tools, CMake, Ninja, Python build deps, etc.
  - Quick run:

  ```bash
  sudo -i && bash scripts/root/setup-build-toolchain.sh
  ```

- scripts/root/setup-system-build-deps.sh
  - Purpose: install basic system build deps and Go toolchain (system-wide).
  - Quick run:

  ```bash
  sudo -i && bash scripts/root/setup-system-build-deps.sh
  ```

- scripts/root/setup-zsh-root.sh
  - Purpose: install Zsh, Oh My Zsh, plugins and Powerlevel10k for root account.
  - Quick run:

  ```bash
  sudo -i && bash scripts/root/setup-zsh-root.sh
  ```

- scripts/root/create-dev-from-root-zsh.sh
  - Purpose: create a `dev` user, copy root's Zsh setup into it, add to docker & sudo groups.
  - Quick run:

  ```bash
  sudo -i && bash scripts/root/create-dev-from-root-zsh.sh
  ```

- scripts/root/setup-ssh-defaults.sh
  - Purpose: create/manage ~/.ssh for a target user, generate ed25519 keypair and authorized_keys.
  - Quick run (for target user `dev`):

  ```bash
  sudo -i && bash scripts/root/setup-ssh-defaults.sh --target-user dev
  ```

- scripts/root/setup-safe-rm.sh
  - Purpose: install `safe-rm`, write a blacklist and place an `rm` wrapper.
  - Quick run:

  ```bash
  sudo -i && bash scripts/root/setup-safe-rm.sh
  ```

- scripts/user/setup-dev-tools-user.sh
  - Purpose: install per-user dev tools (nvm, Node LTS, pnpm, rustup, uv etc.) into $HOME.
  - Quick run (as the target user):

  ```bash
  bash scripts/user/setup-dev-tools-user.sh
  ```
