#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/runtime.env" <<'EOF'
VLESS_UUID=00000000-0000-4000-8000-000000000001
REALITY_PRIVATE_KEY=test-reality-private-key
REALITY_SHORT_ID=0000000000000001
SOCKS_USERNAME=test-user
SOCKS_PASSWORD=test-socks-password
TRANSPORT_PASSWORD=test-transport-password
SNIPROXY_PUBLIC_IPV4=198.51.100.10
TLS_SERVER_NAME=gateway.example.test
TLS_CERT_PATH=/etc/sing-box/server.crt
TLS_KEY_PATH=/etc/sing-box/server.key
SING_BOX_LOG_LEVEL=warn
SKIP_ADMIN_PROVISION=1
EOF
printf '%s\n' 'test-resilient: repository shell syntax'; "$ROOT/scripts/validate-repository.sh"
printf '%s\n' 'test-resilient: minimal profile renders only VLESS + SOCKS'; OUT_DIR="$TMP/minimal" PROFILE=gateway-minimal ENV_FILE="$TMP/runtime.env" "$ROOT/deploy/render.sh"; python3 - "$TMP/minimal/sing-box/config.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); tags={i['tag'] for i in x['inbounds']}; assert tags=={'vless-in','socks-in'}; assert next(i for i in x['inbounds'] if i['tag']=='vless-in')['listen_port']==443
PY
PROFILE=gateway-minimal ENV_FILE="$TMP/runtime.env" OUT_DIR="$TMP/minimal" "$ROOT/deploy/validate.sh"
printf '%s\n' 'test-resilient: resilient profile renders DNS + SS and no disabled transports'; OUT_DIR="$TMP/resilient" PROFILE=gateway-resilient ENV_FILE="$TMP/runtime.env" "$ROOT/deploy/render.sh"; python3 - "$TMP/resilient/sing-box/config.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); by={i['tag']:i for i in x['inbounds']}; assert set(by)=={'vless-in','shadowsocks-in','socks-in'}; assert by['vless-in']['listen_port']==8443; assert by['shadowsocks-in']['listen_port']==8444
PY
PROFILE=gateway-resilient ENV_FILE="$TMP/runtime.env" OUT_DIR="$TMP/resilient" "$ROOT/deploy/validate.sh"; grep -q '^0.0.0.0/0,reject$' "$TMP/resilient/sniproxy/cidr.csv"; grep -q '^::/0,reject$' "$TMP/resilient/sniproxy/cidr.csv"; [[ ! -f "$TMP/resilient/cloudflared/cloudflared.service" ]]
printf '%s\n' 'test-resilient: firewall follows enabled components'; PROFILE=gateway-resilient ENV_FILE="$TMP/runtime.env" DRY_RUN=1 "$ROOT/scripts/apply-firewall.sh" > "$TMP/fw"; grep -q '8443/tcp' "$TMP/fw"; grep -q '8444/tcp' "$TMP/fw"; grep -q 'port 53 proto udp' "$TMP/fw"; grep -q 'port 53 proto tcp' "$TMP/fw"; ! grep -q '8445/tcp' "$TMP/fw"; ! grep -q '8446/tcp' "$TMP/fw"; ! grep -q '8447/udp' "$TMP/fw"; ! grep -q '8448/udp' "$TMP/fw"; ! grep -q '1080/tcp' "$TMP/fw"
printf '%s\n' 'test-resilient: missing DNS public address is rejected'; if OUT_DIR="$TMP/bad" PROFILE=gateway-resilient ENV_FILE=/dev/null "$ROOT/deploy/render.sh" >/dev/null 2>&1; then exit 1; fi
printf '%s\n' 'test-resilient: passed'
