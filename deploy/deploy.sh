#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); ENV_FILE=${ENV_FILE:-"$ROOT/.env"}; PROFILE=default; DRY_RUN=0
while (($#)); do case "$1" in --dry-run) DRY_RUN=1; shift;; --profile) PROFILE=$2; shift 2;; --profile=*) PROFILE=${1#*=}; shift;; --env-file) ENV_FILE=$2; shift 2;; --env-file=*) ENV_FILE=${1#*=}; shift;; *) printf 'usage: %s [--dry-run] [--profile NAME] [--env-file PATH]\n' "$0" >&2; exit 2;; esac; done
[[ "$PROFILE" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'deploy: invalid profile\n' >&2; exit 2; }; PROFILE_FILE="$ROOT/config/profiles/$PROFILE.env.example"; [[ -f "$PROFILE_FILE" ]] || { printf 'deploy: profile not found\n' >&2; exit 1; }
export ENV_FILE DRY_RUN PROFILE
set -a; source "$ROOT/config/defaults.env.example"; source "$PROFILE_FILE"; [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"; [[ -f "$ROOT/config/versions.env" ]] && source "$ROOT/config/versions.env"; set +a
[[ -f /etc/os-release ]] || { printf 'deploy: Debian host required\n' >&2; exit 1; }; source /etc/os-release; [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] || { printf 'deploy: Debian host required\n' >&2; exit 1; }; [[ "$DRY_RUN" == 1 || "$(id -u)" == 0 ]] || { printf 'deploy: root is required\n' >&2; exit 1; }
printf 'deploy: profile=%s\n' "$PROFILE"
if [[ "$DRY_RUN" == 0 ]]; then apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates curl tar ufw; "$ROOT/deploy/backup.sh" create >/dev/null || true; fi
if [[ "$ENABLE_VLESS" == true || "$ENABLE_SHADOWSOCKS" == true || "$ENABLE_VMESS" == true || "$ENABLE_TROJAN" == true || "$ENABLE_HYSTERIA2" == true || "$ENABLE_TUIC" == true || "$ENABLE_SOCKS" == true ]]; then "$ROOT/scripts/install-sing-box.sh"; fi
[[ "$ENABLE_CLOUDFLARED" == true ]] && "$ROOT/scripts/install-cloudflared.sh"
[[ "$ENABLE_DNS_STEERING" == true ]] && "$ROOT/scripts/install-sniproxy.sh"
"$ROOT/deploy/render.sh"
if [[ "${SKIP_ADMIN_PROVISION:-0}" != 1 && "$DRY_RUN" == 0 ]]; then "$ROOT/scripts/create-admin-user.sh"; fi
[[ "$DRY_RUN" == 0 ]] && "$ROOT/scripts/install-ssh-hardening.sh"
"$ROOT/deploy/validate.sh"
"$ROOT/scripts/install-systemd-units.sh"
if [[ "$DRY_RUN" == 0 ]]; then
 "$ROOT/scripts/apply-firewall.sh"; systemctl daemon-reload; systemctl enable --now sing-box.service
 [[ "$ENABLE_CLOUDFLARED" == true ]] && systemctl enable --now cloudflared.service
 [[ "$ENABLE_DNS_STEERING" == true ]] && systemctl enable --now sniproxy.service
 systemctl --no-pager --quiet is-active sing-box.service
else
 "$ROOT/scripts/apply-firewall.sh" --dry-run >/dev/null
fi
if [[ "$DRY_RUN" == 0 && -x "$ROOT/scripts/generate-client-configs.sh" ]]; then
 "$ROOT/scripts/generate-client-configs.sh"
fi
printf 'deploy: deployment complete (profile=%s)\n' "$PROFILE"
