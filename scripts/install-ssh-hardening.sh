#!/usr/bin/env bash
set -euo pipefail
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
BACKUP_ROOT=/var/lib/vps-gateway/ssh-backups
MAIN_CONFIG=/etc/ssh/sshd_config
DROPIN_DIR=/etc/ssh/sshd_config.d
DEST="$DROPIN_DIR/00-vps-gateway-hardening.conf"
fail(){ printf 'ssh-hardening: %s\n' "$1" >&2; exit 1; }
[[ $(id -u) == 0 ]] || fail 'root is required'
[[ -f "$RUNTIME_FILE" ]] || fail 'runtime file missing'
[[ "${SSH_ADMIN_LOGIN_VERIFIED:-}" == YES ]] || fail 'refusing to harden SSH until a separate admin-key login and sudo access have been tested; set SSH_ADMIN_LOGIN_VERIFIED=YES only after verification'
set -a; source "$RUNTIME_FILE"; set +a
[[ "${SSH_PORT:-22}" == 22 ]] || fail 'the node policy requires SSH on TCP/22'
[[ "${ADMIN_USER:-}" =~ ^[a-z][a-z0-9_-]*$ ]] || fail 'ADMIN_USER is missing or invalid'
id "$ADMIN_USER" >/dev/null 2>&1 || fail "admin account does not exist: $ADMIN_USER"
ADMIN_HOME=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
ADMIN_GROUP=$(id -gn "$ADMIN_USER")
AUTHORIZED_KEYS="$ADMIN_HOME/.ssh/authorized_keys"
[[ -s "$AUTHORIZED_KEYS" ]] || fail "admin authorized_keys is empty: $AUTHORIZED_KEYS"
ssh-keygen -lf "$AUTHORIZED_KEYS" >/dev/null 2>&1 || fail "admin authorized_keys contains no parseable public key: $AUTHORIZED_KEYS"
[[ "$(stat -c '%U:%G:%a' "$AUTHORIZED_KEYS")" == "$ADMIN_USER:$ADMIN_GROUP:600" ]] || fail 'admin authorized_keys must be owned by the admin user with mode 0600'
[[ "$(stat -c '%U:%G:%a' "$ADMIN_HOME/.ssh")" == "$ADMIN_USER:$ADMIN_GROUP:700" ]] || fail 'admin .ssh directory must be owned by the admin user with mode 0700'
command -v sshd >/dev/null || fail 'sshd binary is missing'
command -v systemctl >/dev/null || fail 'systemctl is missing'
[[ -f "$MAIN_CONFIG" ]] || fail 'main sshd_config is missing'
stamp=$(date +%Y%m%d-%H%M%S)
backup="$BACKUP_ROOT/$stamp"
install -d -m 0700 "$backup"
cp -a "$MAIN_CONFIG" "$backup/sshd_config"
if [[ -d "$DROPIN_DIR" ]]; then cp -a "$DROPIN_DIR" "$backup/sshd_config.d"; else mkdir -m 0755 "$backup/sshd_config.d"; fi
rollback(){
  printf 'ssh-hardening: restoring previous SSH configuration from %s\n' "$backup" >&2
  cp -a "$backup/sshd_config" "$MAIN_CONFIG"
  rm -rf "$DROPIN_DIR"
  cp -a "$backup/sshd_config.d" "$DROPIN_DIR"
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
}
install -d -m 0755 "$DROPIN_DIR"
tmp=$(mktemp "$DROPIN_DIR/.00-vps-gateway-hardening.XXXXXX")
cat > "$tmp" <<'EOF'
# Managed by vps-gateway-infra; standardized node SSH policy.
Port 22
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
EOF
chmod 0644 "$tmp"
mv "$tmp" "$DEST"
if ! sshd -t -f "$MAIN_CONFIG"; then rollback; fail 'sshd syntax validation failed; previous configuration restored'; fi
effective=$(sshd -T -f "$MAIN_CONFIG" 2>/dev/null) || { rollback; fail 'sshd effective configuration could not be read'; }
for expected in 'port 22' 'pubkeyauthentication yes' 'passwordauthentication no' 'kbdinteractiveauthentication no' 'permitrootlogin no' 'permitemptypasswords no' 'authorizedkeysfile .ssh/authorized_keys' 'allowtcpforwarding no' 'gatewayports no' 'permittunnel no'; do
  grep -Fqx "$expected" <<< "$effective" || { rollback; fail "effective policy mismatch: $expected; previous configuration restored"; }
done
if systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null; then
  printf 'ssh-hardening: policy applied and validated; backup=%s\n' "$backup"
else
  rollback
  fail 'SSH reload failed; previous configuration restored'
fi
