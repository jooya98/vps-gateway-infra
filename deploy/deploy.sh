#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT/.env"}
DRY_RUN=0
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift;;
    --env-file) [[ $# -ge 2 ]] || { printf 'deploy: missing env file\n' >&2; exit 2; }; ENV_FILE=$2; shift 2;;
    --env-file=*) ENV_FILE=${1#*=}; shift;;
    *) printf 'usage: %s [--dry-run] [--env-file PATH]\n' "$0" >&2; exit 2;;
  esac
done
export ENV_FILE DRY_RUN
if [[ -f "$ROOT/config/defaults.env.example" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/config/defaults.env.example"
  set +a
fi
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

printf '%s\n' 'deploy: preflight'
[[ -f /etc/os-release ]] || { printf 'deploy: Debian host required\n' >&2; exit 1; }
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] || { printf 'deploy: Debian host required\n' >&2; exit 1; }
if [[ "$DRY_RUN" == 0 && "$(id -u)" != 0 ]]; then printf 'deploy: root is required unless --dry-run is used\n' >&2; exit 1; fi

if [[ "$DRY_RUN" == 0 ]]; then
  printf '%s\n' 'deploy: install dependencies'
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates curl ufw
else
  printf '%s\n' 'deploy: dependency installation skipped (dry-run)'
fi

printf '%s\n' 'deploy: render templates'
"$ROOT/deploy/render.sh"
printf '%s\n' 'deploy: validate generated configuration'
"$ROOT/deploy/validate.sh"

printf '%s\n' 'deploy: install services'
"$ROOT/scripts/install-sing-box.sh"
"$ROOT/scripts/install-cloudflared.sh"
if [[ "$DRY_RUN" == 0 ]]; then
  "$ROOT/scripts/apply-firewall.sh"
  systemctl daemon-reload
  systemctl enable --now sing-box.service cloudflared.service
  systemctl --no-pager --quiet is-active sing-box.service cloudflared.service
else
  "$ROOT/scripts/apply-firewall.sh" --dry-run >/dev/null
  printf '%s\n' 'deploy: systemd and firewall application skipped (dry-run)'
fi
printf '%s\n' 'deploy: health checks passed'
