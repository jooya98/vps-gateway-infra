#!/usr/bin/env bash
set -euo pipefail

RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
V2RAYN_FILE=${V2RAYN_FILE:-/root/vps-gateway-v2rayn.json}
MIHOMO_FILE=${MIHOMO_FILE:-/root/vps-gateway-mihomo.yaml}

fail() {
  printf 'generate-client-profiles: %s\n' "$1" >&2
  exit 1
}

[[ -f "$RUNTIME_FILE" ]] || fail "runtime file not found: $RUNTIME_FILE"
[[ -f "$CLIENT_INFO_FILE" ]] || fail "client info file not found: $CLIENT_INFO_FILE"

# shellcheck disable=SC1090
set +u
source "$RUNTIME_FILE"
set -u

required=(VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID SOCKS_USERNAME SOCKS_PASSWORD CLOUDFLARED_TUNNEL_TOKEN)
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || fail "$name is missing or empty"
done

# shellcheck disable=SC1090
source "$CLIENT_INFO_FILE"

required=(SERVER PORT UUID REALITY_PUBLIC_KEY REALITY_SHORT_ID FLOW SNI)
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || fail "$name is missing or empty"
done

[[ "$SERVER" =~ ^[0-9a-fA-F:.]+$ ]] || fail 'SERVER must be an IP address'
[[ "$PORT" =~ ^[0-9]+$ ]] || fail 'PORT must be a number'
[[ "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[789abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]] || fail 'UUID format is invalid'
[[ "$REALITY_PUBLIC_KEY" =~ ^[A-Za-z0-9_=-]+$ ]] || fail 'REALITY_PUBLIC_KEY format is invalid'
[[ "$REALITY_SHORT_ID" =~ ^[0-9a-fA-F]{2,64}$ ]] || fail 'REALITY_SHORT_ID format is invalid'
[[ "$FLOW" =~ ^[A-Za-z0-9_-]+$ ]] || fail 'FLOW format is invalid'
[[ "$SNI" =~ ^[A-Za-z0-9.-]+$ ]] || fail 'SNI format is invalid'

runtime_dir=$(dirname "$RUNTIME_FILE")
client_dir=$(dirname "$CLIENT_INFO_FILE")
install -d -m 0700 "$runtime_dir" "$client_dir"

v2rayn_tmp=$(mktemp "$runtime_dir/.vps-gateway-v2rayn.XXXXXX")
mihomo_tmp=$(mktemp "$runtime_dir/.vps-gateway-mihomo.XXXXXX")
cleanup() { rm -f "$v2rayn_tmp" "$mihomo_tmp"; }
trap cleanup EXIT
chmod 0600 "$v2rayn_tmp" "$mihomo_tmp"

cat > "$v2rayn_tmp" <<EOF
{
  "v": "2",
  "ps": "VPS Gateway",
  "add": "$SERVER",
  "port": "$PORT",
  "id": "$UUID",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "tls",
  "sni": "$SNI",
  "alpn": "",
  "fp": "",
  "pbk": "$REALITY_PUBLIC_KEY",
  "sid": "$REALITY_SHORT_ID",
  "spx": "/",
  "scy": "none",
  "flow": "$FLOW",
  "serverName": "",
  "udp": false
}
EOF

cat > "$mihomo_tmp" <<EOF
proxy-groups:
- name: VPS Gateway
  type: vless
  server: $SERVER
  port: $PORT
  uuid: $UUID
  tls: true
  udp: false
  skip-cert-verify: false
  reality-opts:
    public-key: $REALITY_PUBLIC_KEY
    short-id: $REALITY_SHORT_ID
  client-fingerprint: chrome
  servername: $SNI
  flow: $FLOW
EOF

if [[ "$(id -u)" == 0 ]]; then
  chown root:root "$v2rayn_tmp" "$mihomo_tmp"
fi
chmod 0600 "$v2rayn_tmp" "$mihomo_tmp"
mv "$v2rayn_tmp" "$V2RAYN_FILE"
mv "$mihomo_tmp" "$MIHOMO_FILE"

printf 'generate-client-profiles: generated v2rayN profile: %s\n' "$V2RAYN_FILE"
printf 'generate-client-profiles: generated mihomo profile: %s\n' "$MIHOMO_FILE"
printf '%s\n' 'generate-client-profiles: no private keys were printed'