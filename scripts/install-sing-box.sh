#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/.generated"}
DRY_RUN=${DRY_RUN:-0}
[[ -f "$OUT_DIR/sing-box/config.json" ]] || { printf 'sing-box: render configuration first\n' >&2; exit 1; }
if [[ "$DRY_RUN" == 1 ]]; then printf 'sing-box: installation skipped in dry-run\n'; exit 0; fi
[[ "$(id -u)" == 0 ]] || { printf 'sing-box: root is required\n' >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { printf 'sing-box: systemd is required for installation\n' >&2; exit 1; }
[[ -x "${SING_BOX_BIN:-/usr/local/bin/sing-box}" ]] || { printf 'sing-box: install the pinned binary before enabling the service\n' >&2; exit 1; }
install -d -m 0755 /etc/sing-box
install -m 0600 "$OUT_DIR/sing-box/config.json" "${SING_BOX_CONFIG_PATH:-/etc/sing-box/config.json}"
install -m 0644 "$OUT_DIR/sing-box/sing-box.service" /etc/systemd/system/sing-box.service
