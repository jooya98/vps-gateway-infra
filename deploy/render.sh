#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT/.env"}
OUT_DIR=${OUT_DIR:-"$ROOT/.generated"}

if [[ -f "$ROOT/config/defaults.env.example" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/config/defaults.env.example"
  set +a
fi
PROFILE=${PROFILE:-default}
PROFILE_FILE="$ROOT/config/profiles/$PROFILE.env.example"
if [[ -f "$PROFILE_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$PROFILE_FILE"
  set +a
fi
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

required=(VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID SOCKS_USERNAME SOCKS_PASSWORD CLOUDFLARED_TUNNEL_TOKEN SING_BOX_LISTEN_PORT SOCKS_LISTEN_ADDRESS SOCKS_LISTEN_PORT REALITY_SERVER_NAME REALITY_HANDSHAKE_SERVER REALITY_HANDSHAKE_PORT SING_BOX_LOG_LEVEL)
missing=()
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || missing+=("$name")
done
if ((${#missing[@]})); then
  printf 'render: missing required environment variables (%s)\n' "${missing[*]}" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/sing-box" "$OUT_DIR/ssh" "$OUT_DIR/cloudflared"

python3 - "$ROOT" "$OUT_DIR" <<'PY'
import os, re, sys
from pathlib import Path
root, out = map(Path, sys.argv[1:])
files = {
    root / 'templates/sing-box/config.json.tmpl': Path(out / 'sing-box/config.json'),
    root / 'templates/sing-box/sing-box.service.tmpl': Path(out / 'sing-box/sing-box.service'),
    root / 'templates/ssh/99-hardening.conf.tmpl': Path(out / 'ssh/99-hardening.conf'),
    root / 'templates/cloudflared/cloudflared.service.tmpl': Path(out / 'cloudflared/cloudflared.service'),
}
pattern = re.compile(r'\$\{([A-Z][A-Z0-9_]*)\}')
for src, dst in files.items():
    text = src.read_text()
    missing = sorted(set(pattern.findall(text)) - set(os.environ))
    if missing:
        raise SystemExit(f'render: unresolved variables in {src.name}')
    rendered = pattern.sub(lambda m: os.environ[m.group(1)], text)
    dst.write_text(rendered)
    os.chmod(dst, 0o600 if dst.name == 'config.json' else 0o644)
PY
chmod 700 "$OUT_DIR" "$OUT_DIR"/* 2>/dev/null || true
printf 'render: generated configuration under %s\n' "$OUT_DIR"
