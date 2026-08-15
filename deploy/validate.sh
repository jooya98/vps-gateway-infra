#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/.generated"}

# Ensure sshd is present before we attempt any SSH validation
if ! command -v sshd > /dev/null 2>&1; then
  printf 'validate: sshd executable not found – cannot verify SSH hardening\n' >&2
  exit 1
fi

[[ -f "$OUT_DIR/sing-box/config.json" ]] || { printf 'validate: missing generated sing-box config\n' >&2; exit 1; }
[[ -f "$OUT_DIR/ssh/00-vps-gateway-hardening.conf" ]] || { printf 'validate: missing generated SSH hardening config\n' >&2; exit 1; }
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

if grep -RInE '\${[A-Z][A-Z0-9_]*}|(PRIVATE_KEY|SOCKS_PASSWORD|VLESS_UUID|TUNNEL_TOKEN)=' "$OUT_DIR" >/dev/null; then
  printf 'validate: unresolved placeholders or secret assignments found\n' >&2
  exit 1
fi

# Verify the generated hardening file contains the required directives
grep -q '^PasswordAuthentication no$' "$OUT_DIR/ssh/00-vps-gateway-hardening.conf"
grep -q '^PermitRootLogin no$' "$OUT_DIR/ssh/00-vps-gateway-hardening.conf"
grep -q '^PubkeyAuthentication yes$' "$OUT_DIR/ssh/00-vps-gateway-hardening.conf"

# Verify the drop‑in is installed and that the effective sshd config reflects it
if [[ -f /etc/ssh/sshd_config.d/00-vps-gateway-hardening.conf ]]; then
  ssh_cfg=$(sshd -T 2>/dev/null || true)
  printf '%s\n' "$ssh_cfg" | grep -i '^passwordauthentication no$' >/dev/null || { printf 'validate: effective config allows password auth\n' >&2; exit 1; }
  printf '%s\n' "$ssh_cfg" | grep -i '^permitrootlogin no$' >/dev/null || { printf 'validate: effective config permits root login\n' >&2; exit 1; }
  printf '%s\n' "$ssh_cfg" | grep -i '^pubkeyauthentication yes$' >/dev/null || { printf 'validate: effective config disables pubkey auth\n' >&2; exit 1; }
else
  printf 'validate: SSH hardening drop‑in not installed at /etc/ssh/sshd_config.d/00-vps-gateway-hardening.conf\n' >&2
  exit 1
fi

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
