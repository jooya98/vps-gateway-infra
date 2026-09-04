#!/usr/bin/env bash
set -euo pipefail
fail(){ printf 'generate-client-profiles: %s\n' "$1" >&2; exit 1; }
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}; CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
OUT_DIR=${OUT_DIR:-/root/vps-gateway-clients}; V2RAYN_FILE=${V2RAYN_FILE:-$OUT_DIR/v2rayn-vless.json}; MIHOMO_FILE=${MIHOMO_FILE:-$OUT_DIR/mihomo-vless.yaml}; VLESS_FILE=${VLESS_FILE:-$OUT_DIR/vless.txt}
[[ -f "$RUNTIME_FILE" && -f "$CLIENT_INFO_FILE" ]] || fail 'runtime/client-info file missing'
set +u; source "$RUNTIME_FILE"; source "$CLIENT_INFO_FILE"; set -u
for n in SERVER REALITY_PUBLIC_KEY REALITY_SHORT_ID FLOW SNI VLESS_UUID; do [[ -n "${!n:-}" ]] || fail "$n is missing"; done
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); PROFILE=${PROFILE:-default}; ENV_FILE=${ENV_FILE:-}
set -a; source "$ROOT/config/defaults.env.example"; source "$ROOT/config/profiles/$PROFILE.env.example"; [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"; set +a
[[ -n "${VLESS_PORT:-${PORT:-}}" ]] || fail 'VLESS_PORT is missing'; mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR"
write(){ local f=$1; shift; umask 077; printf '%s\n' "$*" > "$f"; chmod 600 "$f"; }
if [[ "$ENABLE_VLESS" == true ]]; then
 host="$SERVER"; [[ "$SERVER" == *:* ]] && host="[$SERVER]"; uri="vless://${VLESS_UUID}@${host}:${VLESS_PORT}?type=tcp&security=reality&pbk=${REALITY_PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${REALITY_SHORT_ID}&flow=${FLOW}#VPS-Gateway"
 write "$VLESS_FILE" "$uri"; cp "$VLESS_FILE" "$OUT_DIR/vless.txt"
 cat > "$V2RAYN_FILE" <<EOF
{"v":"2","ps":"VPS Gateway VLESS","add":"$SERVER","port":"$VLESS_PORT","id":"$VLESS_UUID","aid":"0","net":"tcp","type":"none","tls":"tls","sni":"$SNI","pbk":"$REALITY_PUBLIC_KEY","sid":"$REALITY_SHORT_ID","flow":"$FLOW","udp":false}
EOF
 chmod 600 "$V2RAYN_FILE"
 cat > "$MIHOMO_FILE" <<EOF
proxies:
- name: VPS Gateway VLESS
  type: vless
  server: $SERVER
  port: $VLESS_PORT
  uuid: $VLESS_UUID
  tls: true
  udp: false
  reality-opts:
    public-key: $REALITY_PUBLIC_KEY
    short-id: $REALITY_SHORT_ID
  client-fingerprint: chrome
  servername: $SNI
  flow: $FLOW
EOF
 chmod 600 "$MIHOMO_FILE"
fi
if [[ "$ENABLE_SHADOWSOCKS" == true ]]; then [[ -n "${TRANSPORT_PASSWORD:-}" ]] || fail 'TRANSPORT_PASSWORD required for Shadowsocks'; write "$OUT_DIR/shadowsocks.txt" "ss://$(printf '%s' "${SHADOWSOCKS_METHOD:-chacha20-ietf-poly1305}:$TRANSPORT_PASSWORD" | base64 -w0)@${SERVER}:${SHADOWSOCKS_PORT}#VPS-Gateway-SS"; fi
if [[ "$ENABLE_VMESS" == true ]]; then cat > "$OUT_DIR/vmess.json" <<EOF
{"v":"2","ps":"VPS Gateway VMess","add":"$SERVER","port":"$VMESS_PORT","id":"$VLESS_UUID","aid":"0","scy":"auto","net":"tcp","type":"none","host":"","path":"","tls":"tls","sni":"$TLS_SERVER_NAME"}
EOF
chmod 600 "$OUT_DIR/vmess.json"; fi
if [[ "$ENABLE_TROJAN" == true ]]; then [[ -n "${TRANSPORT_PASSWORD:-}" ]] || fail 'TRANSPORT_PASSWORD required for Trojan'; write "$OUT_DIR/trojan.txt" "trojan://${TRANSPORT_PASSWORD}@${SERVER}:${TROJAN_PORT}?security=tls&sni=${TLS_SERVER_NAME}#VPS-Gateway-Trojan"; fi
if [[ "$ENABLE_HYSTERIA2" == true ]]; then [[ -n "${TRANSPORT_PASSWORD:-}" ]] || fail 'TRANSPORT_PASSWORD required for Hysteria2'; write "$OUT_DIR/hysteria2.txt" "hysteria2://${TRANSPORT_PASSWORD}@${SERVER}:${HYSTERIA2_PORT}/?sni=${TLS_SERVER_NAME}#VPS-Gateway-Hysteria2"; fi
if [[ "$ENABLE_TUIC" == true ]]; then [[ -n "${TRANSPORT_PASSWORD:-}" ]] || fail 'TRANSPORT_PASSWORD required for TUIC'; write "$OUT_DIR/tuic.txt" "tuic://${VLESS_UUID}:${TRANSPORT_PASSWORD}@${SERVER}:${TUIC_PORT}/?sni=${TLS_SERVER_NAME}&congestion_control=bbr#VPS-Gateway-TUIC"; fi
printf 'generate-client-profiles: generated enabled transport artifacts under %s\n' "$OUT_DIR"
printf '%s\n' 'generate-client-profiles: private keys and tunnel tokens were not written to client artifacts'
