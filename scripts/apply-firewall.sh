#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=${DRY_RUN:-0}
POLICY_FILE=${POLICY_FILE:-"$ROOT/config/firewall/policy.env.example"}
PROFILE=gateway
ENV_FILE=${ENV_FILE:-/root/vps-gateway-runtime.conf}
set -a
source "$ROOT/config/defaults.env.example"
source "$POLICY_FILE"
source "$ROOT/config/profiles/gateway.env.example"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
set +a
commands=("ufw --force reset" "ufw default deny incoming" "ufw default allow outgoing")
allow_tcp(){ local port=$1 from=${2:-any}; if [[ "$from" == any ]]; then commands+=("ufw allow ${port}/tcp"); else commands+=("ufw allow from ${from} to any port ${port} proto tcp"); fi; }
allow_udp(){ local port=$1 from=${2:-any}; if [[ "$from" == any ]]; then commands+=("ufw allow ${port}/udp"); else commands+=("ufw allow from ${from} to any port ${port} proto udp"); fi; }
allow_tcp "$SSH_PORT" "$SSH_ALLOW_FROM"
allow_tcp "$REALITY_PORT" "$VLESS_ALLOW_FROM"
allow_tcp "$SHADOWSOCKS_PORT" "$SHADOWSOCKS_ALLOW_FROM"
allow_tcp "$SHADOWSOCKS_2022_PORT" "$SHADOWSOCKS_ALLOW_FROM"
allow_tcp "$SOCKS_LISTEN_PORT" "$SOCKS_ALLOW_FROM"
allow_tcp "$HTTP_PORT" any
allow_udp "$HYSTERIA2_PORT" any
allow_udp "$TUIC_PORT" any
allow_tcp "$TROJAN_PORT" any
allow_tcp "$ANYTLS_PORT" any
allow_tcp "$VLESS_GRPC_PORT" any
commands+=("ufw --force enable")
if [[ "$DRY_RUN" == 1 ]]; then printf '%s\n' "${commands[@]}"; exit 0; fi
[[ $(id -u) == 0 ]] || { printf 'firewall: root is required\n' >&2; exit 1; }
command -v ufw >/dev/null || { printf 'firewall: ufw is not installed\n' >&2; exit 1; }
for line in "${commands[@]}"; do read -r -a argv <<< "$line"; "${argv[@]}" >/dev/null; done
ufw status verbose
