#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT/.env"}
PROFILE=default
DRY_RUN=0
while (($#)); do
 case "$1" in
  --dry-run) DRY_RUN=1; shift;;
  --profile) PROFILE=$2; shift 2;;
  --profile=*) PROFILE=${1#*=}; shift;;
  --env-file) ENV_FILE=$2; shift 2;;
  --env-file=*) ENV_FILE=${1#*=}; shift;;
  *) printf 'usage: %s [--dry-run] [--profile NAME] [--env-file PATH]\n' "$0" >&2; exit 2;;
 esac
done
[[ "$PROFILE" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'deploy: invalid profile\n' >&2; exit 2; }
PROFILE_FILE="$ROOT/config/profiles/$PROFILE.env.example"
[[ -f "$PROFILE_FILE" ]] || { printf 'deploy: profile not found\n' >&2; exit 1; }
export ENV_FILE DRY_RUN PROFILE
set -a
source "$ROOT/config/defaults.env.example"
source "$PROFILE_FILE"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
[[ -f "$ROOT/config/versions.env" ]] && source "$ROOT/config/versions.env"
set +a
[[ -f /etc/os-release ]] || { printf 'deploy: Debian host required\n' >&2; exit 1; }
source /etc/os-release
[[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] || { printf 'deploy: Debian host required\n' >&2; exit 1; }
if [[ "$DRY_RUN" == 0 && "$(id -u)" != 0 ]]; then printf 'deploy: root is required\n' >&2; exit 1; fi
printf 'deploy: profile=%s\n' "$PROFILE"
if [[ "$DRY_RUN" == 0 ]]; then apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates curl tar ufw; fi
if [[ "$ENABLE_VLESS" == true || "$ENABLE_SHADOWSOCKS" == true || "$ENABLE_VMESS" == true || "$ENABLE_TROJAN" == true || "$ENABLE_HYSTERIA2" == true || "$ENABLE_TUIC" == true || "$ENABLE_SOCKS" == true ]]; then
  printf '%s\n' 'deploy: install official sing-box'; "$ROOT/scripts/install-sing-box.sh"
fi
if [[ "$ENABLE_CLOUDFLARED" == true ]]; then printf '%s\n' 'deploy: install optional cloudflared'; "$ROOT/scripts/install-cloudflared.sh"; fi
if [[ "$ENABLE_DNS_STEERING" == true ]]; then printf '%s\n' 'deploy: install optional sniproxy'; "$ROOT/scripts/install-sniproxy.sh"; fi
printf '%s\n' 'deploy: render templates'; "$ROOT/deploy/render.sh"
if [[ "${SKIP_ADMIN_PROVISION:-0}" != 1 && "$DRY_RUN" == 0 ]]; then "$ROOT/scripts/create-admin-user.sh"; fi
if [[ "$DRY_RUN" == 0 ]]; then "$ROOT/scripts/install-ssh-hardening.sh"; fi
printf '%s\n' 'deploy: validate generated configuration'; "$ROOT/deploy/validate.sh"
printf '%s\n' 'deploy: install systemd units'; "$ROOT/scripts/install-systemd-units.sh"
if [[ "$DRY_RUN" == 0 ]]; then
 "$ROOT/deploy/backup.sh" create >/dev/null || true
 "$ROOT/scripts/apply-firewall.sh"
 systemctl daemon-reload
 systemctl enable --now sing-box.service
 if [[ "$ENABLE_CLOUDFLARED" == true ]]; then systemctl enable --now cloudflared.service; fi
 if [[ "$ENABLE_DNS_STEERING" == true ]]; then systemctl enable --now sniproxy.service; fi
 systemctl --no-pager --quiet is-active sing-box.service
else
 "$ROOT/scripts/apply-firewall.sh" --dry-run >/dev/null
fi
printf 'deploy: deployment complete (profile=%s)\n' "$PROFILE"
