#!/usr/bin/env bash
set -euo pipefail

# Move SSH to TCP/22 while temporarily retaining root/password access so the
# newly installed administrator key can be tested before final hardening.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MAIN_CONFIG=/etc/ssh/sshd_config
DROPIN_DIR=/etc/ssh/sshd_config.d
BACKUP_ROOT=/var/lib/vps-gateway/ssh-backups
fail(){ printf 'ssh-port-migration: %s\n' "$1" >&2; exit 1; }
[[ $(id -u) == 0 ]] || fail 'root is required'
command -v sshd >/dev/null || fail 'sshd binary is missing'
command -v systemctl >/dev/null || fail 'systemctl is missing'
[[ -f "$MAIN_CONFIG" ]] || fail 'main sshd_config is missing'

stamp=$(date +%Y%m%d-%H%M%S)
install -d -m 0700 "$BACKUP_ROOT"
backup=$(mktemp -d "$BACKUP_ROOT/$stamp.port-migration.XXXXXX")
cp -a "$MAIN_CONFIG" "$backup/sshd_config"
DROPIN_DIR_EXISTED=0
if [[ -d "$DROPIN_DIR" ]]; then
  cp -a "$DROPIN_DIR" "$backup/sshd_config.d"
  DROPIN_DIR_EXISTED=1
else
  mkdir -m 0755 "$backup/sshd_config.d"
fi

rollback(){
  printf 'ssh-port-migration: restoring prior SSH configuration from %s\n' "$backup" >&2
  cp -a "$backup/sshd_config" "$MAIN_CONFIG"
  rm -rf "$DROPIN_DIR"
  if [[ "$DROPIN_DIR_EXISTED" == 1 ]]; then cp -a "$backup/sshd_config.d" "$DROPIN_DIR"; fi
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
}
install -d -m 0755 "$DROPIN_DIR"
shopt -s nullglob
for file in "$DROPIN_DIR"/*.conf; do
  mv -- "$file" "$backup/disabled-provider-dropins/" 2>/dev/null || {
    install -d -m 0700 "$backup/disabled-provider-dropins"
    mv -- "$file" "$backup/disabled-provider-dropins/" || { shopt -u nullglob; rollback; fail "could not preserve provider fragment: $file"; }
  }
done
shopt -u nullglob

tmp=$(mktemp /etc/ssh/.sshd_config.port-migration.XXXXXX)
cat > "$tmp" <<'EOF'
# Temporary migration policy managed by vps-gateway-infra.
# Root/password login stays available only until the new admin key is tested.
Port 22
AddressFamily any
PubkeyAuthentication yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PermitRootLogin yes
PermitEmptyPasswords no
UsePAM yes
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
PrintMotd no
Subsystem sftp internal-sftp
EOF
chmod 0644 "$tmp"
if ! sshd -t -f "$tmp"; then rm -f "$tmp"; rollback; fail 'temporary SSH configuration failed validation'; fi
effective=$(sshd -T -f "$tmp" 2>/dev/null) || { rm -f "$tmp"; rollback; fail 'could not inspect temporary SSH configuration'; }
grep -Fqx 'port 22' <<< "$effective" || { rm -f "$tmp"; rollback; fail 'temporary SSH policy does not listen on TCP/22'; }
mv "$tmp" "$MAIN_CONFIG"
if systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null; then
  printf 'ssh-port-migration: SSH now listens on TCP/22; root/password access remains temporarily enabled; backup=%s\n' "$backup"
else
  rollback
  fail 'SSH reload failed; previous configuration restored'
fi
