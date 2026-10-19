#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
command -v sing-box >/dev/null || { printf 'test-gateway-profile: sing-box is required\n' >&2; exit 1; }
REALITY_PRIVATE_KEY=$(sing-box generate reality-keypair | awk '/PrivateKey/{print $2}')
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=gateway.example.test' -keyout "$TMP/server.key" -out "$TMP/server.crt" >/dev/null 2>&1
cat > "$TMP/runtime.env" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000001
REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
REALITY_SHORT_ID=0000000000000001
SOCKS_USERNAME=test-user
SOCKS_PASSWORD=test-socks-password
TRANSPORT_PASSWORD=test-transport-password
TLS_SERVER_NAME=gateway.example.test
TLS_CERT_PATH=$TMP/server.crt
TLS_KEY_PATH=$TMP/server.key
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflared-token
SING_BOX_LOG_LEVEL=warn
EOF
OUT_DIR="$TMP/generated" PROFILE=gateway ENV_FILE="$TMP/runtime.env" "$ROOT/deploy/render.sh"
OUT_DIR="$TMP/generated" PROFILE=gateway ENV_FILE="$TMP/runtime.env" "$ROOT/deploy/validate.sh"
python3 - "$TMP/generated/sing-box/config.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
tags={i["tag"] for i in x["inbounds"]}
assert "vless-in" in tags and "socks-in" in tags
assert x["outbounds"] == [{"type":"direct","tag":"direct"}]
vless=next(i for i in x["inbounds"] if i["tag"]=="vless-in")
assert vless["listen_port"] == 8443
assert vless["tls"]["reality"]["enabled"] is True
PY
printf '%s\n' 'test-gateway-profile: passed'
