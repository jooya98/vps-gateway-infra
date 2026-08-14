#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/.generated"}
DRY_RUN=${DRY_RUN:-0}
if [[ "$DRY_RUN" == 1 ]]; then printf '%s\n' 'systemd: unit installation skipped in dry-run'; exit 0; fi
[[ "$(id -u)" == 0 ]] || { printf 'systemd: root is required\n' >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { printf 'systemd: systemctl is required\n' >&2; exit 1; }
[[ -f "$OUT_DIR/sing-box/config.json" && -f "$OUT_DIR/sing-box/sing-box.service" ]] || { printf 'systemd: sing-box render output missing\n' >&2; exit 1; }
[[ -f "$OUT_DIR/cloudflared/cloudflared.service" ]] || { printf 'systemd: cloudflared render output missing\n' >&2; exit 1; }
[[ -n "${CLOUDFLARED_TUNNEL_TOKEN:-}" ]] || { printf 'systemd: cloudflared token is required\n' >&2; exit 1; }
install -d -m 0755 /etc/sing-box
install -m 0600 "$OUT_DIR/sing-box/config.json" "${SING_BOX_CONFIG_PATH:-/etc/sing-box/config.json}"
install -m 0644 "$OUT_DIR/sing-box/sing-box.service" /etc/systemd/system/sing-box.service
install -d -m 0700 /etc/cloudflared
printf '%s' "$CLOUDFLARED_TUNNEL_TOKEN" > "${CLOUDFLARED_TOKEN_PATH:-/etc/cloudflared/token}"
chmod 0600 "${CLOUDFLARED_TOKEN_PATH:-/etc/cloudflared/token}"
install -m 0644 "$OUT_DIR/cloudflared/cloudflared.service" /etc/systemd/system/cloudflared.service
