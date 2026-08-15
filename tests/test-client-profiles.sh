#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
RUNTIME="$TMP/runtime.conf"
CLIENT="$TMP/client-info.txt"
V2RAYN="$TMP/v2rayn.json"
MIHOMO="$TMP/mihomo.yaml"

cat > "$RUNTIME" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
EOF

cat > "$CLIENT" <<EOF
SERVER=127.0.0.1
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=test-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF

printf '%s\n' 'test-client-profiles: generate profiles with test values'
RUNTIME_FILE="$RUNTIME" CLIENT_INFO_FILE="$CLIENT" V2RAYN_FILE="$V2RAYN" MIHOMO_FILE="$MIHOMO" "$ROOT/scripts/generate-client-profiles.sh"

! grep -q 'test-private-key\|test-socks-password\|test-cloudflare-token' "$V2RAYN"
! grep -q 'test-private-key\|test-socks-password\|test-cloudflare-token' "$MIHOMO"
[[ "$(stat -c '%a' "$V2RAYN")" == 600 ]]
[[ "$(stat -c '%a' "$MIHOMO")" == 600 ]]
if [[ "$(id -u)" == 0 ]]; then
  [[ "$(stat -c '%u' "$V2RAYN")" == 0 ]]
  [[ "$(stat -c '%u' "$MIHOMO")" == 0 ]]
fi

printf '%s\n' 'test-client-profiles: passed'