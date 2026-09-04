#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
DEST_DIR=/etc/ssh/sshd_config.d
DEST="$DEST_DIR/00-vps-gateway-hardening.conf"
[[ $(id -u) == 0 ]] || { printf 'ssh-hardening: root is required\n' >&2; exit 1; }
[[ -f "$RUNTIME_FILE" ]] || { printf 'ssh-hardening: runtime file missing\n' >&2; exit 1; }
set -a; source "$RUNTIME_FILE"; set +a
mkdir -p "$DEST_DIR"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
# Managed by vps-gateway-infra. Do not edit on the host.
Port $SSH_PORT
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
EOF
if [[ -f "$DEST" ]]; then cp -a "$DEST" "$DEST.bak.$(date +%s)"; fi
install -m 0644 "$TMP" "$DEST"
sshd -t
if systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null; then
  printf 'ssh-hardening: sshd reloaded on port %s\n' "$SSH_PORT"
else
  printf '%s\n' 'ssh-hardening: could not reload sshd/ssh' >&2
  exit 1
fi
