#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=${DRY_RUN:-0}
POLICY_FILE=${POLICY_FILE:-"$ROOT/config/firewall/policy.env.example"}
PROFILE=${PROFILE:-default}
set -a
source "$ROOT/config/defaults.env.example"
source "$ROOT/config/profiles/$PROFILE.env.example"
source "$POLICY_FILE"
[[ -f "${ENV_FILE:-}" ]] && source "$ENV_FILE"
set +a

commands=("ufw --force reset" "ufw default deny incoming" "ufw default allow outgoing")
allow_tcp() { local port=$1 from=$2; if [[ "$from" == any ]]; then commands+=("ufw allow ${port}/tcp"); else commands+=("ufw allow from ${from} to any port ${port} proto tcp"); fi; }
allow_udp() { local port=$1 from=$2; if [[ "$from" == any ]]; then commands+=("ufw allow ${port}/udp"); else commands+=("ufw allow from ${from} to any port ${port} proto udp"); fi; }
allow_tcp "$SSH_PORT" "$SSH_ALLOW_FROM"
[[ "${ENABLE_VLESS:-false}" == true ]] && allow_tcp "$VLESS_PORT" "$VLESS_ALLOW_FROM"
[[ "${ENABLE_SHADOWSOCKS:-false}" == true ]] && allow_tcp "$SHADOWSOCKS_PORT" "$SHADOWSOCKS_ALLOW_FROM"
[[ "${ENABLE_VMESS:-false}" == true ]] && allow_tcp "$VMESS_PORT" "$VMESS_ALLOW_FROM"
[[ "${ENABLE_TROJAN:-false}" == true ]] && allow_tcp "$TROJAN_PORT" "$TROJAN_ALLOW_FROM"
[[ "${ENABLE_HYSTERIA2:-false}" == true ]] && allow_udp "$HYSTERIA2_PORT" "$HYSTERIA2_ALLOW_FROM"
[[ "${ENABLE_TUIC:-false}" == true ]] && allow_udp "$TUIC_PORT" "$TUIC_ALLOW_FROM"
[[ "${ENABLE_DNS_STEERING:-false}" == true ]] && { allow_udp "$DNS_PORT" "$DNS_ALLOW_FROM"; allow_tcp "$DNS_PORT" "$DNS_ALLOW_FROM"; }
if [[ "${ALLOW_PUBLIC_SOCKS:-false}" == true ]]; then allow_tcp "$SOCKS_PORT" "$SOCKS_ALLOW_FROM"; fi
commands+=("ufw --force enable")

if [[ "$DRY_RUN" == 1 ]]; then printf '%s\n' "${commands[@]}"; exit 0; fi
[[ "$(id -u)" == 0 ]] || { printf 'firewall: root is required\n' >&2; exit 1; }
command -v ufw >/dev/null 2>&1 || { printf 'firewall: ufw is not installed\n' >&2; exit 1; }
for line in "${commands[@]}"; do read -r -a argv <<< "$line"; "${argv[@]}" >/dev/null; done
ufw status verbose
