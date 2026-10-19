#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
SSH_TEMPLATE="$ROOT/templates/ssh/sshd_config.tmpl"
BACKUP_ROOT=/var/lib/vps-gateway/ssh-backups
MAIN_CONFIG=/etc/ssh/sshd_config
DROPIN_DIR=/etc/ssh/sshd_config.d
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
[[ -f "$SSH_TEMPLATE" ]] || fail "SSH policy template is missing: $SSH_TEMPLATE"

stamp=$(date +%Y%m%d-%H%M%S)
install -d -m 0700 "$BACKUP_ROOT"
backup=$(mktemp -d "$BACKUP_ROOT/$stamp.XXXXXX")
cp -a "$MAIN_CONFIG" "$backup/sshd_config"
DROPIN_DIR_EXISTED=0
if [[ -d "$DROPIN_DIR" ]]; then
  cp -a "$DROPIN_DIR" "$backup/sshd_config.d"
  DROPIN_DIR_EXISTED=1
else
  mkdir -m 0755 "$backup/sshd_config.d"
fi

ROLLBACK_NEEDED=0
rollback(){
  printf 'ssh-hardening: restoring previous SSH configuration from %s\n' "$backup" >&2
  cp -a "$backup/sshd_config" "$MAIN_CONFIG"
  rm -rf "$DROPIN_DIR"
  if [[ "$DROPIN_DIR_EXISTED" == 1 ]]; then
    cp -a "$backup/sshd_config.d" "$DROPIN_DIR"
  fi
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  ROLLBACK_NEEDED=0
}
on_exit(){
  status=$?
  if [[ "$ROLLBACK_NEEDED" == 1 ]]; then rollback; fi
  exit "$status"
}
trap on_exit EXIT

# The node policy owns the main config. Preserve provider drop-ins in the backup,
# but move them out of the active path so Match blocks cannot override this policy.
ROLLBACK_NEEDED=1
install -d -m 0755 "$DROPIN_DIR"
install -d -m 0700 "$backup/disabled-provider-dropins"
shopt -s nullglob
for file in "$DROPIN_DIR"/*.conf; do
  mv -- "$file" "$backup/disabled-provider-dropins/" || { shopt -u nullglob; rollback; fail "could not disable provider SSH fragment: $file"; }
done
shopt -u nullglob

tmp=$(mktemp /etc/ssh/.sshd_config.vps-gateway.XXXXXX)
cp "$SSH_TEMPLATE" "$tmp"
chmod 0644 "$tmp"
mv "$tmp" "$MAIN_CONFIG"

if ! sshd -t -f "$MAIN_CONFIG"; then rollback; fail 'sshd syntax validation failed; previous configuration restored'; fi
effective=$(sshd -T -f "$MAIN_CONFIG" 2>/dev/null) || { rollback; fail 'sshd effective configuration could not be read'; }
for expected in 'port 22' 'pubkeyauthentication yes' 'passwordauthentication no' 'kbdinteractiveauthentication no' 'permitrootlogin no' 'permitemptypasswords no' 'authorizedkeysfile .ssh/authorized_keys' 'allowtcpforwarding no' 'gatewayports no' 'permittunnel no'; do
  grep -Fqx "$expected" <<< "$effective" || { rollback; fail "effective policy mismatch: $expected; previous configuration restored"; }
done
if systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null; then
  ROLLBACK_NEEDED=0
  trap - EXIT
  printf 'ssh-hardening: policy applied and validated; backup=%s\n' "$backup"
else
  rollback
  fail 'SSH reload failed; previous configuration restored'
fi
