#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
PROFILE=${PROFILE:-gateway}

fail(){ printf 'validate-secrets: %s\n' "$1" >&2; exit 1; }
[[ -f "$RUNTIME_FILE" ]] || fail "runtime file not found: $RUNTIME_FILE"
[[ -f "$CLIENT_INFO_FILE" ]] || fail "client info file not found: $CLIENT_INFO_FILE"
[[ -f "$ROOT/config/defaults.env.example" ]] || fail 'defaults file not found'
[[ -f "$ROOT/config/profiles/$PROFILE.env.example" ]] || fail "profile not found: $PROFILE"
set -a; source "$ROOT/config/defaults.env.example"; source "$ROOT/config/profiles/$PROFILE.env.example"; source "$RUNTIME_FILE"; set +a

check_private_mode(){ local file=$1 mode owner; mode=$(stat -c '%a' "$file") || fail "could not inspect permissions: $file"; owner=$(stat -c '%u' "$file") || fail "could not inspect owner: $file"; (( (8#$mode & 077) == 0 )) || fail "file permissions are broader than 0600: $file"; [[ "$owner" == 0 ]] || fail "file is not owned by root: $file"; }
check_private_mode "$RUNTIME_FILE"; check_private_mode "$CLIENT_INFO_FILE"

required=(VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID SOCKS_USERNAME SOCKS_PASSWORD SSH_PORT TRANSPORT_PASSWORD CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_NAME PUBLIC_HOSTNAME DIRECT_HOSTNAME CLOUDFLARE_TUNNEL_NAME)
for name in "${required[@]}"; do [[ -n "${!name:-}" ]] || fail "$name is missing or empty"; done
[[ "$SSH_PORT" =~ ^[1-9][0-9]{0,4}$ ]] || fail 'SSH_PORT format is invalid'; (( SSH_PORT <= 65535 )) || fail 'SSH_PORT is outside TCP port range'
[[ "$VLESS_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[789abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]] || fail 'VLESS_UUID format is invalid'
[[ "$REALITY_PRIVATE_KEY" =~ ^[A-Za-z0-9_=-]+$ ]] || fail 'REALITY_PRIVATE_KEY format is invalid'
[[ "$REALITY_SHORT_ID" =~ ^[0-9a-fA-F]{2,64}$ ]] || fail 'REALITY_SHORT_ID format is invalid'
[[ "$SOCKS_USERNAME" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'SOCKS_USERNAME format is invalid'
[[ "$CLOUDFLARE_TUNNEL_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || fail 'Cloudflare Tunnel name is invalid'
for host in "$PUBLIC_HOSTNAME" "$DIRECT_HOSTNAME"; do [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || fail "invalid hostname: $host"; [[ "$host" == *".$CLOUDFLARE_ZONE_NAME" ]] || fail "hostname outside Cloudflare zone: $host"; done
[[ "$PUBLIC_HOSTNAME" != "$DIRECT_HOSTNAME" ]] || fail 'PUBLIC_HOSTNAME and DIRECT_HOSTNAME must differ'
if grep -Fq 'REALITY_PRIVATE_KEY' "$CLIENT_INFO_FILE"; then fail 'client info contains the private-key variable name'; fi
if grep -Fq "$REALITY_PRIVATE_KEY" "$CLIENT_INFO_FILE"; then fail 'client info contains the private key'; fi
printf 'validate-secrets: runtime and client information are valid (profile=%s)\n' "$PROFILE"
