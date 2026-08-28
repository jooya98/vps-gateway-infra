#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/.generated"}; PROFILE=${PROFILE:-default}; ENV_FILE=${ENV_FILE:-"$ROOT/.env"}; DRY_RUN=${DRY_RUN:-0}
set -a; source "$ROOT/config/defaults.env.example"; source "$ROOT/config/profiles/$PROFILE.env.example"; [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"; set +a
if [[ "$DRY_RUN" == 1 ]]; then printf 'systemd: dry-run profile=%s\n' "$PROFILE"; exit 0; fi
[[ "$(id -u)" == 0 ]] || { printf 'systemd: root is required\n' >&2; exit 1; }; command -v systemctl >/dev/null || { printf 'systemd: systemctl is required\n' >&2; exit 1; }
install -d -m 0755 /etc/sing-box; install -m 0600 "$OUT_DIR/sing-box/config.json" "$SING_BOX_CONFIG_PATH"; install -m 0644 "$OUT_DIR/sing-box/sing-box.service" /etc/systemd/system/sing-box.service
install -d -m 0755 /etc/ssh/sshd_config.d; install -m 0644 "$OUT_DIR/ssh/00-vps-gateway-hardening.conf" /etc/ssh/sshd_config.d/00-vps-gateway-hardening.conf
if [[ "$ENABLE_CLOUDFLARED" == true ]]; then
 [[ -f "$OUT_DIR/cloudflared/cloudflared.service" && -n "${CLOUDFLARED_TUNNEL_TOKEN:-}" ]] || { printf 'systemd: cloudflared output/token missing\n' >&2; exit 1; }
 install -d -m 0700 /etc/cloudflared; printf '%s' "$CLOUDFLARED_TUNNEL_TOKEN" > "$CLOUDFLARED_TOKEN_PATH"; chmod 0600 "$CLOUDFLARED_TOKEN_PATH"; install -m 0644 "$OUT_DIR/cloudflared/cloudflared.service" /etc/systemd/system/cloudflared.service
fi
if [[ "$ENABLE_DNS_STEERING" == true ]]; then
 install -d -m 0755 /etc/sniproxy /var/lib/sniproxy; install -m 0644 "$OUT_DIR/sniproxy/config.yaml" "$SNIPROXY_CONFIG_PATH"; install -m 0644 "$OUT_DIR/sniproxy/domains.csv" "$SNIPROXY_DOMAINS_PATH"; install -m 0644 "$OUT_DIR/sniproxy/cidr.csv" "$SNIPROXY_CIDR_PATH"
 sed -e "s|\${SNIPROXY_BIN}|$SNIPROXY_BIN|g" -e "s|\${SNIPROXY_CONFIG_PATH}|$SNIPROXY_CONFIG_PATH|g" "$ROOT/templates/sniproxy/sniproxy.service.tmpl" > /etc/systemd/system/sniproxy.service
 chmod 0644 /etc/systemd/system/sniproxy.service
fi
