#!/usr/bin/env bash
set -euo pipefail

# test-client-profiles.sh
# Validates generation of client profiles for IPv4 and IPv6, ensuring no secret leakage,
# correct permissions, and proper VLESS URI formatting.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_test() {
  local runtime_file=$1 client_file=$2 v2rayn=$3 mihomo=$4 vless=$5
  RUNTIME_FILE="$runtime_file" CLIENT_INFO_FILE="$client_file" \
    V2RAYN_FILE="$v2rayn" MIHOMO_FILE="$mihomo" VLESS_FILE="$vless" \
    "$ROOT/scripts/generate-client-profiles.sh"

  # Ensure private values are not present in any output
  ! grep -q 'test-private-key\|test-socks-password\|test-cloudflare-token' "$v2rayn"
  ! grep -q 'test-private-key\|test-socks-password\|test-cloudflare-token' "$mihomo"
  ! grep -q 'test-private-key\|test-socks-password\|test-cloudflare-token' "$vless"

  # Verify permissions are 0600 (owner root if running as root)
  [[ "$(stat -c '%a' "$v2rayn")" == 600 ]]
  [[ "$(stat -c '%a' "$mihomo")" == 600 ]]
  [[ "$(stat -c '%a' "$vless")" == 600 ]]
  if [[ "$(id -u)" == 0 ]]; then
    [[ "$(stat -c '%u' "$v2rayn")" == 0 ]]
    [[ "$(stat -c '%u' "$mihomo")" == 0 ]]
    [[ "$(stat -c '%u' "$vless")" == 0 ]]
  fi

  # Validate VLESS URI components (including IPv4/IPv6 handling)
  grep -q '^vless://00000000-0000-4000-8000-000000000002@' "$vless"
  grep -q 'type=tcp' "$vless"
  grep -q 'security=reality' "$vless"
  grep -q 'pbk=test-public-key' "$vless"
  grep -q 'fp=chrome' "$vless"
  grep -q 'sni=www.cloudflare.com' "$vless"
  grep -q 'sid=abcdef0123456789' "$vless"
  grep -q 'flow=xtls-rprx-vision' "$vless"
  grep -q '#VPS-Gateway' "$vless"
}

# IPv4 test setup
RUNTIME_IPV4="$TMP/runtime-ipv4.conf"
CLIENT_IPV4="$TMP/client-ipv4.txt"
V2RAYN_IPV4="$TMP/v2rayn-ipv4.json"
MIHOMO_IPV4="$TMP/mihomo-ipv4.yaml"
VLESS_IPV4="$TMP/vless-ipv4.txt"

cat > "$RUNTIME_IPV4" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
EOF

cat > "$CLIENT_IPV4" <<EOF
SERVER=127.0.0.1
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=test-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF

run_test "$RUNTIME_IPV4" "$CLIENT_IPV4" "$V2RAYN_IPV4" "$MIHOMO_IPV4" "$VLESS_IPV4"

# IPv6 test setup
RUNTIME_IPV6="$TMP/runtime-ipv6.conf"
CLIENT_IPV6="$TMP/client-ipv6.txt"
V2RAYN_IPV6="$TMP/v2rayn-ipv6.json"
MIHOMO_IPV6="$TMP/mihomo-ipv6.yaml"
VLESS_IPV6="$TMP/vless-ipv6.txt"

cat > "$RUNTIME_IPV6" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
EOF

cat > "$CLIENT_IPV6" <<EOF
SERVER=2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=test-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF

run_test "$RUNTIME_IPV6" "$CLIENT_IPV6" "$V2RAYN_IPV6" "$MIHOMO_IPV6" "$VLESS_IPV6"

printf 'test-client-profiles: passed\n'
