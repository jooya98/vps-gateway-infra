#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/.generated"}

[[ -f "$OUT_DIR/sing-box/config.json" ]] || { printf 'validate: missing generated sing-box config\n' >&2; exit 1; }
[[ -f "$OUT_DIR/ssh/99-hardening.conf" ]] || { printf 'validate: missing generated SSH config\n' >&2; exit 1; }
[[ -f "$OUT_DIR/cloudflared/cloudflared.service" ]] || { printf 'validate: missing generated cloudflared unit\n' >&2; exit 1; }
[[ -f "$OUT_DIR/sing-box/sing-box.service" ]] || { printf 'validate: missing generated sing-box unit\n' >&2; exit 1; }

python3 - "$OUT_DIR/sing-box/config.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
assert len(data['inbounds']) == 2
assert data['inbounds'][0]['type'] == 'vless'
assert data['inbounds'][0]['tls']['reality']['enabled'] is True
assert data['inbounds'][1]['type'] == 'socks'
assert data['outbounds'][0]['type'] == 'direct'
PY

if grep -RInE '\$\{[A-Z][A-Z0-9_]*\}|(PRIVATE_KEY|SOCKS_PASSWORD|VLESS_UUID|TUNNEL_TOKEN)=' "$OUT_DIR" >/dev/null; then
  printf 'validate: unresolved placeholders or secret assignments found\n' >&2
  exit 1
fi

grep -q '^ExecStart=.*tunnel run --token-file ' "$OUT_DIR/cloudflared/cloudflared.service"
grep -q '^ExecStart=.* run -c ' "$OUT_DIR/sing-box/sing-box.service"
grep -q '^PasswordAuthentication no$' "$OUT_DIR/ssh/99-hardening.conf"
grep -q '^PermitRootLogin no$' "$OUT_DIR/ssh/99-hardening.conf"

if command -v systemd-analyze >/dev/null 2>&1; then
  for unit in "$OUT_DIR/cloudflared/cloudflared.service" "$OUT_DIR/sing-box/sing-box.service"; do
    unit_output=$(systemd-analyze verify "$unit" 2>&1) || {
      # A clean test container intentionally lacks the installed service
      # binaries. Still reject all unit errors other than that expected case.
      if printf '%s\n' "$unit_output" | grep -vE 'Command .* is not executable: No such file or directory' | grep -q .; then
        printf 'validate: systemd unit validation failed\n' >&2
        exit 1
      fi
    }
  done
fi

printf 'validate: generated configuration is valid\n'
