#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/.generated"}
DRY_RUN=${DRY_RUN:-0}
[[ -f "$OUT_DIR/cloudflared/cloudflared.service" ]] || { printf 'cloudflared: render configuration first\n' >&2; exit 1; }
if [[ "$DRY_RUN" == 1 ]]; then printf 'cloudflared: installation skipped in dry-run\n'; exit 0; fi
[[ "$(id -u)" == 0 ]] || { printf 'cloudflared: root is required\n' >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { printf 'cloudflared: systemd is required for installation\n' >&2; exit 1; }
[[ -x "${CLOUDFLARED_BIN:-/usr/bin/cloudflared}" ]] || { printf 'cloudflared: install the pinned binary before enabling the service\n' >&2; exit 1; }
[[ -n "${CLOUDFLARED_TUNNEL_TOKEN:-}" ]] || { printf 'cloudflared: token is required\n' >&2; exit 1; }
install -d -m 0700 /etc/cloudflared
printf '%s' "$CLOUDFLARED_TUNNEL_TOKEN" > "${CLOUDFLARED_TOKEN_PATH:-/etc/cloudflared/token}"
chmod 0600 "${CLOUDFLARED_TOKEN_PATH:-/etc/cloudflared/token}"
install -m 0644 "$OUT_DIR/cloudflared/cloudflared.service" /etc/systemd/system/cloudflared.service
