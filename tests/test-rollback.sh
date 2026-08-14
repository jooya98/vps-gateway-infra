#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target=$(mktemp -d)
backups=$(mktemp -d)
trap 'rm -rf "$target" "$backups"' EXIT
mkdir -p "$target/etc/sing-box" "$target/etc/systemd/system" "$target/etc/cloudflared" "$target/etc/ufw"
printf old-config > "$target/etc/sing-box/config.json"
printf old-unit > "$target/etc/systemd/system/sing-box.service"
printf old-token > "$target/etc/cloudflared/token"
printf old-cf-unit > "$target/etc/systemd/system/cloudflared.service"
printf old-rules > "$target/etc/ufw/user.rules"
backup_dir=$(BACKUP_ROOT="$backups" TARGET_ROOT="$target" "$ROOT/deploy/backup.sh" create)
printf new-config > "$target/etc/sing-box/config.json"
printf new-token > "$target/etc/cloudflared/token"
printf new-rules > "$target/etc/ufw/user.rules"
TARGET_ROOT="$target" "$ROOT/deploy/rollback.sh" "$backup_dir" >/dev/null
printf old-config | cmp -s - "$target/etc/sing-box/config.json"
printf old-token | cmp -s - "$target/etc/cloudflared/token"
printf old-rules | cmp -s - "$target/etc/ufw/user.rules"
printf '%s\n' 'rollback-test: passed'
