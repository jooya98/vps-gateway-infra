#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/.generated"}
PROFILE=${PROFILE:-default}
[[ -f "$OUT_DIR/sing-box/config.json" ]] || { printf 'validate: missing generated sing-box config\n' >&2; exit 1; }
python3 - "$OUT_DIR/sing-box/config.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert isinstance(x.get('inbounds'),list) and x['inbounds']
assert x.get('outbounds') == [{'type':'direct','tag':'direct'}]
for i in x['inbounds']:
    assert i.get('tag') and i.get('listen_port')
    if i['type'] == 'vless': assert i['tls']['reality']['enabled'] is True
    if i['type'] in {'vmess','trojan','hysteria2','tuic'}:
        assert i['tls']['enabled'] is True
        assert i['tls'].get('certificate_path') and i['tls'].get('key_path')
PY
[[ -f "$OUT_DIR/ssh/00-vps-gateway-hardening.conf" ]] || { printf 'validate: missing SSH hardening output\n' >&2; exit 1; }
grep -q '^PasswordAuthentication no$' "$OUT_DIR/ssh/00-vps-gateway-hardening.conf"
grep -q '^PermitRootLogin no$' "$OUT_DIR/ssh/00-vps-gateway-hardening.conf"
if [[ "${ENABLE_DNS_STEERING:-false}" == true ]]; then
  [[ -f "$OUT_DIR/sniproxy/config.yaml" && -f "$OUT_DIR/sniproxy/domains.csv" && -f "$OUT_DIR/sniproxy/cidr.csv" ]] || { printf 'validate: DNS steering outputs missing\n' >&2; exit 1; }
  grep -q '^0.0.0.0/0,reject$' "$OUT_DIR/sniproxy/cidr.csv"
  grep -q '^::/0,reject$' "$OUT_DIR/sniproxy/cidr.csv"
fi
if [[ "${ENABLE_CLOUDFLARED:-false}" == true ]]; then [[ -f "$OUT_DIR/cloudflared/cloudflared.service" ]] || exit 1; fi
if command -v sing-box >/dev/null 2>&1; then sing-box check -c "$OUT_DIR/sing-box/config.json"; fi
if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "$OUT_DIR/sing-box/sing-box.service" >/dev/null 2>&1 || true
  if [[ -f "$OUT_DIR/cloudflared/cloudflared.service" ]]; then systemd-analyze verify "$OUT_DIR/cloudflared/cloudflared.service" >/dev/null 2>&1 || true; fi
  if [[ -f "$OUT_DIR/sniproxy/sniproxy.service" ]]; then systemd-analyze verify "$OUT_DIR/sniproxy/sniproxy.service" >/dev/null 2>&1 || true; fi
fi
if grep -RInE '\$\{[A-Z][A-Z0-9_]*\}|(PRIVATE_KEY|SOCKS_PASSWORD|VLESS_UUID|TUNNEL_TOKEN)=[^[:space:]]+' "$OUT_DIR" >/dev/null; then printf 'validate: unresolved placeholders or secret assignments found\n' >&2; exit 1; fi
printf 'validate: profile=%s generated configuration is valid\n' "$PROFILE"
