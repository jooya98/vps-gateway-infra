#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=${DRY_RUN:-0}
POLICY_FILE=${POLICY_FILE:-"$ROOT/config/firewall/policy.env.example"}
PROFILE=${PROFILE:-gateway}
ENV_FILE=${ENV_FILE:-${RUNTIME_FILE:-}}
set -a
source "$ROOT/config/defaults.env.example"
source "$POLICY_FILE"
source "$ROOT/config/profiles/$PROFILE.env.example"
[[ -n "$ENV_FILE" && -f "$ENV_FILE" ]] && source "$ENV_FILE"
set +a
fail(){ printf 'firewall: %s\n' "$1" >&2; exit 1; }
[[ "$SSH_PORT" == 22 ]] || fail 'the node policy requires SSH on TCP/22'
for port in "$SSH_PORT" "$VLESS_PORT" "$SHADOWSOCKS_PORT" "$SHADOWSOCKS_2022_PORT" "$TROJAN_PORT" "$HYSTERIA2_PORT" "$TUIC_PORT" "$ANYTLS_PORT" "$VLESS_GRPC_PORT" "$SOCKS_LISTEN_PORT" "$HTTP_PORT"; do
  [[ -n "${port:-}" ]] || continue
  [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)) || fail "invalid port: $port"
done
commands=()
allow_tcp(){ local port=$1 from=$2; if [[ "$from" == any ]]; then commands+=("ufw allow ${port}/tcp"); else commands+=("ufw allow from ${from} to any port ${port} proto tcp"); fi; }
allow_udp(){ local port=$1 from=$2; if [[ "$from" == any ]]; then commands+=("ufw allow ${port}/udp"); else commands+=("ufw allow from ${from} to any port ${port} proto udp"); fi; }
# Add the management rule first. Never reset UFW: unrelated rules belong to the host.
allow_tcp "$SSH_PORT" "$SSH_ALLOW_FROM"
[[ "$ENABLE_VLESS" == true ]] && allow_tcp "$VLESS_PORT" "$VLESS_ALLOW_FROM"
[[ "$ENABLE_SHADOWSOCKS" == true ]] && allow_tcp "$SHADOWSOCKS_PORT" "$SHADOWSOCKS_ALLOW_FROM"
[[ "$ENABLE_SHADOWSOCKS" == true ]] && allow_tcp "$SHADOWSOCKS_2022_PORT" "$SHADOWSOCKS_ALLOW_FROM"
[[ "$ENABLE_TROJAN" == true ]] && allow_tcp "$TROJAN_PORT" "$TROJAN_ALLOW_FROM"
[[ "$ENABLE_HYSTERIA2" == true ]] && allow_udp "$HYSTERIA2_PORT" "$HYSTERIA2_ALLOW_FROM"
[[ "$ENABLE_TUIC" == true ]] && allow_udp "$TUIC_PORT" "$TUIC_ALLOW_FROM"
[[ "${ENABLE_DIRECT_TLS:-0}" == 1 ]] && allow_tcp "$ANYTLS_PORT" "$TROJAN_ALLOW_FROM"
[[ "${ENABLE_DIRECT_TLS:-0}" == 1 ]] && allow_tcp "$VLESS_GRPC_PORT" "$TROJAN_ALLOW_FROM"
[[ "$ENABLE_SOCKS" == true && "${ALLOW_PUBLIC_SOCKS:-false}" == true ]] && allow_tcp "$SOCKS_LISTEN_PORT" "$SOCKS_ALLOW_FROM"
[[ "$ENABLE_SOCKS" == true && "${ALLOW_PUBLIC_SOCKS:-false}" == true ]] && allow_tcp "$HTTP_PORT" "$SOCKS_ALLOW_FROM"
if [[ "$DRY_RUN" == 1 ]]; then
  printf '%s\n' "${commands[@]}"
  printf '%s\n' 'ufw default deny incoming' 'ufw default allow outgoing' 'ufw --force enable'
  exit 0
fi
[[ $(id -u) == 0 ]] || fail 'root is required'
command -v ufw >/dev/null || fail 'ufw is not installed'
for line in "${commands[@]}"; do read -r -a argv <<< "$line"; "${argv[@]}" >/dev/null; done
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw --force enable >/dev/null
ufw status verbose
