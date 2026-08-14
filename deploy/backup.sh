#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT=${BACKUP_ROOT:-/var/backups/vps-gateway-infra}
TARGET_ROOT=${TARGET_ROOT:-/}
if [[ "${1:-}" != create ]]; then
  printf 'usage: %s create\n' "$0" >&2
  exit 2
fi
[[ "$TARGET_ROOT" != / || "$(id -u)" == 0 ]] || { printf 'backup: root is required\n' >&2; exit 1; }

stamp=$(date -u +%Y%m%dT%H%M%SZ)
dir="$BACKUP_ROOT/$stamp"
install -d -m 0700 "$dir"
manifest="$dir/manifest"
: > "$manifest"
paths=(
  /etc/sing-box/config.json
  /etc/systemd/system/sing-box.service
  /etc/cloudflared/token
  /etc/systemd/system/cloudflared.service
  /etc/ufw/user.rules
  /etc/ufw/user6.rules
)
for path in "${paths[@]}"; do
  rel=${path#/}
  source="$TARGET_ROOT/$rel"
  printf '%s\n' "$rel" >> "$manifest"
  if [[ -e "$source" ]]; then
    install -d -m 0700 "$dir/$(dirname "$rel")"
    cp -a "$source" "$dir/$rel"
  fi
done
if [[ "$TARGET_ROOT" == / ]] && command -v ufw >/dev/null 2>&1; then
  ufw status verbose > "$dir/ufw-status-before.txt" 2>/dev/null || true
fi
chmod 0600 "$manifest" "$dir/ufw-status-before.txt" 2>/dev/null || true
printf '%s\n' "$dir"
