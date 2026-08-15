#!/usr/bin/env bash
set -euo pipefail

# generate-client-profiles.sh
# Generates three client artifacts:
#   1. v2rayN JSON configuration
#   2. mihomo YAML configuration
#   3. VLESS URI for Reality clients
# Reads a runtime file and a client‑info file, validates required variables,
# builds the artifacts, ensures 0600 permissions, and optionally sets root ownership.

fail() {
  printf 'generate-client-profiles: %s\n' "$1" >&2
  exit 1
}

# Default file locations (production layout)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
V2RAYN_FILE=${V2RAYN_FILE:-/root/vps-gateway-v2rayn.json}
MIHOMO_FILE=${MIHOMO_FILE:-/root/vps-gateway-mihomo.yaml}
VLESS_FILE=${VLESS_FILE:-/root/vps-gateway-vless.txt}

[[ -f "$RUNTIME_FILE" ]] || fail "runtime file not found: $RUNTIME_FILE"
[[ -f "$CLIENT_INFO_FILE" ]] || fail "client info file not found: $CLIENT_INFO_FILE"

# Load variables
set +u
source "$RUNTIME_FILE"
source "$CLIENT_INFO_FILE"
set -u

# Required variables
required_runtime=(VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID SOCKS_USERNAME SOCKS_PASSWORD CLOUDFLARED_TUNNEL_TOKEN)
required_client=(SERVER PORT UUID REALITY_PUBLIC_KEY REALITY_SHORT_ID FLOW SNI)
for name in "${required_runtime[@]}"; do
  [[ -n "${!name:-}" ]] || fail "$name is missing or empty"
 done
for name in "${required_client[@]}"; do
  [[ -n "${!name:-}" ]] || fail "$name is missing or empty"
 done

# Basic validation
[[ "$SERVER" =~ ^[0-9a-fA-F:.]+$ ]] || fail 'SERVER must be an IP address'
[[ "$PORT" =~ ^[0-9]+$ ]] || fail 'PORT must be a number'
[[ "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[789abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]] || fail 'UUID format is invalid'
[[ "$REALITY_PUBLIC_KEY" =~ ^[A-Za-z0-9_=-]+$ ]] || fail 'REALITY_PUBLIC_KEY format is invalid'
[[ "$REALITY_SHORT_ID" =~ ^[0-9a-fA-F]{2,64}$ ]] || fail 'REALITY_SHORT_ID format is invalid'
[[ "$FLOW" =~ ^[A-Za-z0-9_-]+$ ]] || fail 'FLOW format is invalid'
[[ "$SNI" =~ ^[A-Za-z0-9.-]+$ ]] || fail 'SNI format is invalid'

# Prepare temporary files in same directories as final outputs
runtime_dir=$(dirname "$RUNTIME_FILE")
client_dir=$(dirname "$CLIENT_INFO_FILE")
install -d -m 0700 "$runtime_dir" "$client_dir"

v2rayn_tmp=$(mktemp "$runtime_dir/.vps-gateway-v2rayn.XXXXXX")
mihomo_tmp=$(mktemp "$runtime_dir/.vps-gateway-mihomo.XXXXXX")
vless_tmp=$(mktemp "$runtime_dir/.vps-gateway-vless.XXXXXX")
chmod 0600 "$v2rayn_tmp" "$mihomo_tmp" "$vless_tmp"

# v2rayN JSON
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

# mihomo YAML
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

# VLESS URI (IPv6 handling)
if [[ "$SERVER" =~ : ]]; then
  vless_server="[$SERVER]"
else
  vless_server="$SERVER"
fi
vless_uri="vless://${UUID}@${vless_server}:${PORT}?type=tcp&security=reality&pbk=${REALITY_PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${REALITY_SHORT_ID}&flow=${FLOW}#VPS-Gateway"
cat > "$vless_tmp" <<EOF
$vless_uri
EOF

# Apply root ownership if running as root
if [[ "$(id -u)" == 0 ]]; then
  chown root:root "$v2rayn_tmp" "$mihomo_tmp" "$vless_tmp"
fi
chmod 0600 "$v2rayn_tmp" "$mihomo_tmp" "$vless_tmp"

# Move to final locations
mv "$v2rayn_tmp" "$V2RAYN_FILE"
mv "$mihomo_tmp" "$MIHOMO_FILE"
mv "$vless_tmp" "$VLESS_FILE"

printf 'generate-client-profiles: generated v2rayN profile: %s\n' "$V2RAYN_FILE"
printf 'generate-client-profiles: generated mihomo profile: %s\n' "$MIHOMO_FILE"
printf 'generate-client-profiles: generated VLESS URI: %s\n' "$VLESS_FILE"
printf '%s\n' 'generate-client-profiles: no private keys were printed'

exit 0