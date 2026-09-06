#!/usr/bin/env bash
set -euo pipefail

RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
BACKUP_ROOT=/var/lib/vps-gateway/ssh-provider-backup
DEST_DIR=/etc/ssh/sshd_config.d
DEST="$DEST_DIR/00-vps-gateway-hardening.conf"
MAIN_CONFIG=/etc/ssh/sshd_config
[[ $(id -u) == 0 ]] || { printf 'ssh-hardening: root is required\n' >&2; exit 1; }
[[ -f "$RUNTIME_FILE" ]] || { printf 'ssh-hardening: runtime file missing\n' >&2; exit 1; }
set -a; source "$RUNTIME_FILE"; set +a
[[ "${SSH_PORT:-22}" == 22 ]] || { printf 'ssh-hardening: gateway SSH port must be 22\n' >&2; exit 1; }

# The gateway owns the OpenSSH server policy. Preserve provider/cloud-init fragments
# for forensics, but never load them into the active sshd configuration.
install -d -m 0755 "$DEST_DIR"
shopt -s nullglob
provider_files=("$DEST_DIR"/*.conf)
if ((${#provider_files[@]})); then
  stamp=$(date +%Y%m%d-%H%M%S)
  backup_dir="$BACKUP_ROOT/$stamp"
  install -d -m 0700 "$backup_dir"
  for file in "${provider_files[@]}"; do
    [[ "$file" == "$DEST" ]] && continue
    mv -- "$file" "$backup_dir/"
  done
fi
shopt -u nullglob

cat > "$MAIN_CONFIG" <<'EOF'
# Managed by vps-gateway-infra. Do not edit on the host.
Port 22
AddressFamily any

HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
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
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

rm -f "$DEST"
sshd -t
printf '%s\n' 'ssh-hardening: effective SSH policy validated'
if systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null; then
  printf '%s\n' 'ssh-hardening: sshd reloaded on port 22'
else
  printf '%s\n' 'ssh-hardening: could not reload sshd/ssh' >&2
  exit 1
fi
