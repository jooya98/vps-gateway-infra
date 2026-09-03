#!/usr/bin/env bash
set -euo pipefail

RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
OUT_DIR=${OUT_DIR:-/root/vps-gateway-clients}

[[ -f "$RUNTIME_FILE" ]] || { echo "client-configs: missing runtime file $RUNTIME_FILE" >&2; exit 1; }

set -a
source "$RUNTIME_FILE"
set +a

SERVER_IP=${SNIPROXY_PUBLIC_IPV4:-${PUBLIC_IPV4:-}}
if [[ -z "$SERVER_IP" ]]; then
  SERVER_IP=$(curl -4 -fsS https://api.ipify.org || true)
fi

[[ -n "${VLESS_UUID:-}" ]] || { echo "client-configs: missing VLESS_UUID" >&2; exit 1; }
mkdir -p "$OUT_DIR"/{vless,socks5}

cat > "$OUT_DIR/vless/vless-uri.txt" <<EOF
vless://${VLESS_UUID}@${SERVER_IP}:${VLESS_PORT:-8443}?type=tcp&security=reality&pbk=${REALITY_PUBLIC_KEY:-}&sid=${REALITY_SHORT_ID:-}#Joohar-Gateway
EOF

cat > "$OUT_DIR/socks5/proxy-uri.txt" <<EOF
socks5://${SOCKS_USERNAME:-}:${SOCKS_PASSWORD:-}@${SERVER_IP}:${SOCKS_PORT:-1080}
EOF

cat > "$OUT_DIR/summary.txt" <<EOF
Joohar Gateway Client Bundle

Server: ${SERVER_IP}
VLESS port: ${VLESS_PORT:-8443}
SOCKS port: ${SOCKS_PORT:-1080}
Generated: $(date -u)
EOF

chmod -R go-rwx "$OUT_DIR"
echo "client-configs: generated bundle: $OUT_DIR"
