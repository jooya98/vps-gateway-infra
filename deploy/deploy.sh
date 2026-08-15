#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT/.env"}
PROFILE=default
DRY_RUN=0
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift;;
    --profile) [[ $# -ge 2 ]] || { printf 'deploy: missing profile\n' >&2; exit 2; }; PROFILE=$2; shift 2;;
    --profile=*) PROFILE=${1#*=}; shift;;
    --env-file) [[ $# -ge 2 ]] || { printf 'deploy: missing env file\n' >&2; exit 2; }; ENV_FILE=$2; shift 2;;
    --env-file=*) ENV_FILE=${1#*=}; shift;;
    *) printf 'usage: %s [--dry-run] [--profile NAME] [--env-file PATH]\n' "$0" >&2; exit 2;;
  esac
done
[[ "$PROFILE" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'deploy: invalid profile name\n' >&2; exit 2; }
PROFILE_FILE="$ROOT/config/profiles/$PROFILE.env.example"
[[ -f "$PROFILE_FILE" ]] || { printf 'deploy: profile not found\n' >&2; exit 1; }
export ENV_FILE DRY_RUN PROFILE
if [[ -f "$ROOT/config/defaults.env.example" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/config/defaults.env.example"
  set +a
fi
if [[ -f "$ROOT/config/versions.env.example" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/config/versions.env.example"
  set +a
fi
if [[ -f "$ROOT/config/versions.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/config/versions.env"
  set +a
fi
printf '%s\n' 'deploy: preflight'
[[ -f /etc/os-release ]] || { printf 'deploy: Debian host required\n' >&2; exit 1; }
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] || { printf 'deploy: Debian host required\n' >&2; exit 1; }
if [[ "$DRY_RUN" == 0 && "$(id -u)" != 0 ]]; then printf 'deploy: root is required unless --dry-run is used\n' >&2; exit 1; fi

if [[ "$DRY_RUN" == 0 ]]; then
  if [[ "${SING_BOX_VERSION:-latest}" == latest || "${CLOUDFLARED_VERSION:-latest}" == latest ]]; then
    printf '%s\n' 'deploy: WARNING: latest upstream versions are not reproducible; pin config/versions.env for production' >&2
  fi
fi

if [[ "$DRY_RUN" == 0 ]]; then
  printf '%s\n' 'deploy: install dependencies'
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates curl tar ufw
else
  printf '%s\n' 'deploy: install dependencies (dry-run; skipped)'
fi

if [[ "$DRY_RUN" == 0 ]]; then
  BACKUP_DIR=$("$ROOT/deploy/backup.sh" create)
  printf '%s\n' 'deploy: managed-state backup created'
fi

printf '%s\n' 'deploy: install official sing-box'
"$ROOT/scripts/install-sing-box.sh"
printf '%s\n' 'deploy: install official cloudflared'
"$ROOT/scripts/install-cloudflared.sh"

printf '%s\n' 'deploy: load profile and secrets'
set -a
# shellcheck disable=SC1090
source "$PROFILE_FILE"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
set +a

printf '%s\n' 'deploy: render templates'
"$ROOT/deploy/render.sh"

# Create administrative user (interactive, can be skipped with SKIP_ADMIN_PROVISION=1)
if [[ "${SKIP_ADMIN_PROVISION:-0}" != "1" ]]; then
  printf '%s\n' 'deploy: create admin user (interactive)'
  "$ROOT/scripts/create-admin-user.sh"
else
  printf '%s\n' 'deploy: admin user provisioning skipped (SKIP_ADMIN_PROVISION=1)'
fi

printf '%s\n' 'deploy: install SSH hardening drop‑in'
"$ROOT/scripts/install-ssh-hardening.sh"
printf '%s\n' 'deploy: validate generated configuration'
"$ROOT/deploy/validate.sh"

printf '%s\n' 'deploy: install systemd units'
"$ROOT/scripts/install-systemd-units.sh"
if [[ "$DRY_RUN" == 0 ]]; then
  "$ROOT/scripts/apply-firewall.sh"
  systemctl daemon-reload
  systemctl enable --now sing-box.service cloudflared.service
  systemctl --no-pager --quiet is-active sing-box.service cloudflared.service
  printf '%s\n' 'deploy: services enabled and started'
else
  "$ROOT/scripts/apply-firewall.sh" --dry-run >/dev/null
  printf '%s\n' 'deploy: systemd and firewall application skipped (dry-run)'
fi
printf '%s\n' 'deploy: deployment complete'
