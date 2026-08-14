# VPS Gateway Infrastructure

Minimal, reproducible Debian gateway configuration rebuilt from the preserved
`echo-kit` reference artifact.

## Safety boundary

`reference/` is forensic input. It must not be edited, sanitized in place, or
copied directly to a host. The original snapshot contains credentials. Runtime
configuration is generated from templates using externally supplied variables.

No real `.env` file is included. Start from `.env.example` and keep secrets
outside Git.

## First milestone

Render and validate the expected sing-box, SSH, cloudflared, and firewall
configuration from a clean Debian container or host. Real service installation
is intentionally separate and requires explicit root execution.

## Usage

```sh
cp .env.example .env
# Fill secrets locally; do not commit .env.
# For reproducible installs, override versions from config/versions.env.example.
./deploy/deploy.sh --dry-run --env-file .env
```

Profiles are selected with `--profile default` or `--profile gateway-minimal`.
Only the minimal gateway services are currently implemented; Docker and
monitoring profiles are intentionally not present yet.

A real deployment requires root on Debian and explicit installation settings.
The deploy script validates rendered files before changing system state.

## Layout

- `reference/`: immutable forensic artifact and extraction
- `templates/`: sanitized runtime templates
- `config/`: non-secret defaults and firewall policy
- `deploy/`: orchestration, rendering, and validation
- `scripts/`: service installation and firewall application
- `bootstrap/`: declarative clean-Debian base package installation
- `tests/`: shell, leakage, bootstrap, and disposable-container checks
- `docs/`: architecture, bootstrap, and operational assumptions

## Base OS bootstrap

The operator package layer is explicit and separate from service deployment:

```sh
cp config/packages.env.example config/packages.env
sudo ./bootstrap/01-base-packages.sh
```

It installs only the packages declared in `config/packages.env`; it does not
create users, change shells, configure SSH/firewall, install Docker, or add
services. See `docs/bootstrap.md`.
