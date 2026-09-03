#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
PROFILE=${PROFILE:-gateway-minimal}

fail() {
  printf 'validate-secrets: %s\n' "$1" >&2
  exit 1
}

[[ -f "$RUNTIME_FILE" ]] || fail "runtime file not found: $RUNTIME_FILE"
[[ -f "$CLIENT_INFO_FILE" ]] || fail "client info file not found: $CLIENT_INFO_FILE"
[[ -f "$ROOT/config/defaults.env.example" ]] || fail 'defaults file not found'
[[ -f "$ROOT/config/profiles/$PROFILE.env.example" ]] || fail "profile not found: $PROFILE"

# Load only feature flags/defaults. Secrets are loaded separately below.
set -a
# shellcheck disable=SC1091
source "$ROOT/config/defaults.env.example"
# shellcheck disable=SC1091
source "$ROOT/config/profiles/$PROFILE.env.example"
set +a

check_private_mode() {
  local file=$1 mode owner
  mode=$(stat -c '%a' "$file") || fail "could not inspect permissions: $file"
  owner=$(stat -c '%u' "$file") || fail "could not inspect owner: $file"
  (( (8#$mode & 077) == 0 )) || fail "file permissions are broader than 0600: $file"
  if [[ "$(id -u)" == 0 || "$file" == /root/vps-gateway-runtime.conf || "$file" == /root/vps-gateway-client-info.txt ]]; then
    [[ "$owner" == 0 ]] || fail "file is not owned by root: $file"
  fi
}

check_private_mode "$RUNTIME_FILE"
check_private_mode "$CLIENT_INFO_FILE"

# shellcheck disable=SC1090
set +u
source "$RUNTIME_FILE"
set -u

required=(VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID SOCKS_USERNAME SOCKS_PASSWORD)
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || fail "$name is missing or empty"
done

if [[ "${ENABLE_SHADOWSOCKS:-false}" == true || "${ENABLE_VMESS:-false}" == true || "${ENABLE_TROJAN:-false}" == true || "${ENABLE_HYSTERIA2:-false}" == true || "${ENABLE_TUIC:-false}" == true ]]; then
  [[ -n "${TRANSPORT_PASSWORD:-}" ]] || fail 'TRANSPORT_PASSWORD is missing or empty'
fi

if [[ "${ENABLE_DNS_STEERING:-false}" == true ]]; then
  [[ -n "${SNIPROXY_PUBLIC_IPV4:-}" ]] || fail 'SNIPROXY_PUBLIC_IPV4 is missing or empty'
  [[ "$SNIPROXY_PUBLIC_IPV4" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail 'SNIPROXY_PUBLIC_IPV4 format is invalid'
  [[ ! "$SNIPROXY_PUBLIC_IPV4" =~ ^(10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\. ]] || fail 'SNIPROXY_PUBLIC_IPV4 is private'
fi

if [[ "${ENABLE_CLOUDFLARED:-false}" == true ]]; then
  [[ -n "${CLOUDFLARED_TUNNEL_TOKEN:-}" ]] || fail 'CLOUDFLARED_TUNNEL_TOKEN is missing or empty'
fi

[[ "$VLESS_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[789abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]] || fail 'VLESS_UUID format is invalid'
[[ "$REALITY_PRIVATE_KEY" =~ ^[A-Za-z0-9_=-]+$ ]] || fail 'REALITY_PRIVATE_KEY format is invalid'
[[ "$REALITY_SHORT_ID" =~ ^[0-9a-fA-F]{2,64}$ ]] || fail 'REALITY_SHORT_ID format is invalid'
[[ "$SOCKS_USERNAME" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'SOCKS_USERNAME format is invalid'
if [[ -n "${TRANSPORT_PASSWORD:-}" ]]; then
  [[ "$TRANSPORT_PASSWORD" =~ ^[A-Za-z0-9_=-]+$ ]] || fail 'TRANSPORT_PASSWORD format is invalid'
fi

if grep -Fq 'REALITY_PRIVATE_KEY' "$CLIENT_INFO_FILE"; then
  fail 'client info contains the private-key variable name'
fi
if grep -Fq "$REALITY_PRIVATE_KEY" "$CLIENT_INFO_FILE"; then
  fail 'client info contains the private key'
fi

printf 'validate-secrets: runtime and client information are valid (profile=%s)\n' "$PROFILE"
