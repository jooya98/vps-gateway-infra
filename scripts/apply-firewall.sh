#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=${DRY_RUN:-0}
RESET_UFW=${RESET_UFW:-1}
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
# Add management and enabled gateway rules. The final policy intentionally replaces provider UFW rules; migration mode preserves them until admin access is verified.
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

# The Tailscale exit-node script records the WAN interface after opt-in setup.
# If a later gateway deployment resets UFW, restore the required forwarding rule.
TAILSCALE_EXIT_NODE_STATE_FILE=${TAILSCALE_EXIT_NODE_STATE_FILE:-/etc/vps-gateway/tailscale-exit-node.conf}
if [[ -f "$TAILSCALE_EXIT_NODE_STATE_FILE" ]]; then
  TAILSCALE_WAN_IF=$(sed -n 's/^WAN_IF=//p' "$TAILSCALE_EXIT_NODE_STATE_FILE")
  [[ "$TAILSCALE_WAN_IF" =~ ^[-A-Za-z0-9_.:]{1,15}$ ]] || fail "invalid WAN_IF in Tailscale state file: $TAILSCALE_EXIT_NODE_STATE_FILE"
  commands+=("ufw route allow in on tailscale0 out on $TAILSCALE_WAN_IF")
fi

if [[ "$DRY_RUN" == 1 ]]; then
  [[ "$RESET_UFW" == 1 ]] && printf '%s\n' 'ufw --force reset'
  printf '%s\n' "${commands[@]}"
  printf '%s\n' 'ufw default deny incoming' 'ufw default allow outgoing' 'ufw --force enable'
  exit 0
fi
[[ $(id -u) == 0 ]] || fail 'root is required'
command -v ufw >/dev/null || fail 'ufw is not installed'
command -v sshd >/dev/null || fail 'sshd is not installed; refusing to enable UFW without a verified SSH policy'
effective_ssh=$(sshd -T 2>/dev/null) || fail 'could not read effective sshd configuration; UFW was not changed'
grep -Fqx 'port 22' <<< "$effective_ssh" || fail 'sshd is not configured to listen on TCP/22; refusing to enable UFW before SSH migration'
if [[ "$RESET_UFW" == 1 ]]; then ufw --force reset >/dev/null; fi
for line in "${commands[@]}"; do read -r -a argv <<< "$line"; "${argv[@]}" >/dev/null; done
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw --force enable >/dev/null
ufw status verbose
