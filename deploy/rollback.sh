#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT=${BACKUP_ROOT:-/var/backups/vps-gateway-infra}
TARGET_ROOT=${TARGET_ROOT:-/}
backup_dir=${1:-}
if [[ -z "$backup_dir" ]]; then
  backup_dir=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | sed -n '1s/^[^ ]* //p')
fi
[[ -n "$backup_dir" && -f "$backup_dir/manifest" ]] || { printf 'rollback: backup directory with manifest is required\n' >&2; exit 1; }
[[ "$TARGET_ROOT" != / || "$(id -u)" == 0 ]] || { printf 'rollback: root is required\n' >&2; exit 1; }

while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  target="$TARGET_ROOT/$rel"
  source="$backup_dir/$rel"
  if [[ -e "$source" ]]; then
    install -d -m 0755 "$(dirname "$target")"
    mode=0644
    [[ "$rel" == etc/sing-box/config.json || "$rel" == etc/cloudflared/token ]] && mode=0600
    install -m "$mode" "$source" "$target"
  else
    rm -f "$target"
  fi
done < "$backup_dir/manifest"

if [[ "$TARGET_ROOT" == / ]] && command -v ufw >/dev/null 2>&1; then
  ufw --force enable >/dev/null
  ufw reload >/dev/null 2>&1 || true
fi
if [[ "$TARGET_ROOT" == / ]] && command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl try-restart sing-box.service cloudflared.service >/dev/null 2>&1 || true
fi
printf '%s\n' "rollback: restored managed state from $backup_dir"
