#!/usr/bin/env bash
set -euo pipefail

RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
SING_BOX_BIN=${SING_BOX_BIN:-/usr/local/bin/sing-box}
SOCKS_USERNAME=${SOCKS_USERNAME:-gateway}
SERVER=${SERVER:-}

if [[ "$(id -u)" != 0 && ( "$RUNTIME_FILE" == /root/vps-gateway-runtime.conf || "$CLIENT_INFO_FILE" == /root/vps-gateway-client-info.txt ) ]]; then
  printf 'generate-secrets: root is required for default output paths\n' >&2
  exit 1
fi
command -v openssl >/dev/null 2>&1 || {
  printf 'generate-secrets: openssl is required\n' >&2
  exit 1
}
[[ -x "$SING_BOX_BIN" ]] || {
  printf 'generate-secrets: sing-box binary is required: %s\n' "$SING_BOX_BIN" >&2
  exit 1
}
[[ ! -e "$RUNTIME_FILE" ]] || {
  printf 'generate-secrets: refusing to overwrite existing runtime file: %s\n' "$RUNTIME_FILE" >&2
  printf '%s\n' 'generate-secrets: delete it only after deliberately rotating gateway credentials' >&2
  exit 1
}
[[ ! -e "$CLIENT_INFO_FILE" ]] || {
  printf 'generate-secrets: refusing to overwrite existing client info: %s\n' "$CLIENT_INFO_FILE" >&2
  exit 1
}
[[ "$SOCKS_USERNAME" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'generate-secrets: SOCKS_USERNAME must contain only letters, numbers, dot, underscore, or hyphen\n' >&2
  exit 1
}

runtime_dir=$(dirname "$RUNTIME_FILE")
client_dir=$(dirname "$CLIENT_INFO_FILE")
install -d -m 0700 "$runtime_dir" "$client_dir"
runtime_tmp=$(mktemp "$runtime_dir/.vps-gateway-runtime.XXXXXX")
client_tmp=$(mktemp "$client_dir/.vps-gateway-client-info.XXXXXX")
cleanup() { rm -f "$runtime_tmp" "$client_tmp"; }
trap cleanup EXIT
chmod 0600 "$runtime_tmp" "$client_tmp"

if command -v uuidgen >/dev/null 2>&1; then
  VLESS_UUID=$(uuidgen)
elif "$SING_BOX_BIN" generate uuid >/dev/null 2>&1; then
  VLESS_UUID=$("$SING_BOX_BIN" generate uuid)
else
  raw_uuid=$(openssl rand -hex 16)
  VLESS_UUID="${raw_uuid:0:8}-${raw_uuid:8:4}-4${raw_uuid:13:3}-8${raw_uuid:17:3}-${raw_uuid:20:12}"
fi

keypair_output=$(
  "$SING_BOX_BIN" generate reality-keypair 2>/dev/null
) || {
  printf 'generate-secrets: sing-box Reality keypair generation failed\n' >&2
  exit 1
}
REALITY_PRIVATE_KEY=$(awk -F': *' '$1 == "PrivateKey" { print $2; exit }' <<< "$keypair_output")
REALITY_PUBLIC_KEY=$(awk -F': *' '$1 == "PublicKey" { print $2; exit }' <<< "$keypair_output")
[[ -n "$REALITY_PRIVATE_KEY" && -n "$REALITY_PUBLIC_KEY" ]] || {
  printf 'generate-secrets: could not parse sing-box Reality keypair output\n' >&2
  exit 1
}

REALITY_SHORT_ID=$(openssl rand -hex 8)
SOCKS_PASSWORD=$(openssl rand -hex 24)

cat > "$runtime_tmp" <<EOF
# Generated once for this gateway. Keep mode 0600 and outside Git.
VLESS_UUID=$VLESS_UUID
REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
SOCKS_USERNAME=$SOCKS_USERNAME
SOCKS_PASSWORD=$SOCKS_PASSWORD
CLOUDFLARED_TUNNEL_TOKEN=
EOF
cat > "$client_tmp" <<EOF
# Non-sensitive client parameters. Set SERVER manually after provisioning.
SERVER=$SERVER
PORT=443
UUID=$VLESS_UUID
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF

if [[ "$(id -u)" == 0 ]]; then
  chown root:root "$runtime_tmp" "$client_tmp"
fi
chmod 0600 "$runtime_tmp" "$client_tmp"
mv "$runtime_tmp" "$RUNTIME_FILE"
mv "$client_tmp" "$CLIENT_INFO_FILE"

printf 'generate-secrets: generated runtime file: %s\n' "$RUNTIME_FILE"
printf 'generate-secrets: generated client info: %s\n' "$CLIENT_INFO_FILE"
printf '%s\n' 'generate-secrets: CLOUDFLARED_TUNNEL_TOKEN is empty; add it manually before deployment'
printf '%s\n' 'generate-secrets: credentials were not printed'
