# Base OS Bootstrap Layer

The base package layer prepares a clean Debian VPS with a minimal operator and
debugging environment. It is declarative: package names are maintained in
`config/packages.env`, while `bootstrap/01-base-packages.sh` performs the
installation.

## Responsibilities

The layer provides:

- common transfer and archive tools
- Git and terminal/operator tools
- shell completion and an additional shell binary
- system and network debugging tools
- GnuPG and Debian release metadata helpers for future container-host work

It does not configure the user environment. In particular, it does not:

- create users or change the default shell
- install dotfiles, aliases, prompts, or terminal customizations
- configure SSH or the firewall
- install Docker, Kubernetes, monitoring, or other services
- restart services or reboot the host

## Usage

On a clean Debian VPS:

```sh
cd /path/to/vps-gateway-infra
cp config/packages.env.example config/packages.env
sudo ./bootstrap/01-base-packages.sh
```

The real `config/packages.env` is ignored by Git. The script deliberately does
not use `config/packages.env.example` automatically, so an operator must make
the local configuration choice explicitly.

For inspection without changing the machine:

```sh
DRY_RUN=1 ./bootstrap/01-base-packages.sh
```

Dry-run still requires a Debian host and a local `config/packages.env`, but it
does not invoke APT.

The script is idempotent: rerunning it updates the package index and asks APT
to install the same declared package set. It does not remove packages outside
this profile.
