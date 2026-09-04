#!/usr/bin/env bash
set -euo pipefail

# Idempotent provisioning of a non-root administrative user.
if [[ $(id -u) != 0 ]]; then
  printf 'admin: root is required\n' >&2
  exit 1
fi

ADMIN_USER=${ADMIN_USER:-}
if [[ -z "$ADMIN_USER" ]]; then
  while true; do
    read -r -p 'Admin username: ' ADMIN_USER
    [[ "$ADMIN_USER" =~ ^[a-z][a-z0-9_-]*$ ]] && break
    printf '%s\n' 'Invalid username.' >&2
  done
fi

id "$ADMIN_USER" >/dev/null 2>&1 || {
  while true; do
    read -r -s -p "Initial password for $ADMIN_USER: " PASS1; printf '\n'
    read -r -s -p 'Confirm password: ' PASS2; printf '\n'
    [[ -n "$PASS1" && "$PASS1" == "$PASS2" ]] && break
    printf '%s\n' 'Passwords do not match or are empty.' >&2
  done
  useradd -m -s /bin/bash "$ADMIN_USER"
  printf '%s:%s\n' "$ADMIN_USER" "$PASS1" | chpasswd
  unset PASS1 PASS2
}

usermod -aG sudo "$ADMIN_USER"

mkdir -p "/home/$ADMIN_USER/.ssh"
chmod 700 "/home/$ADMIN_USER/.ssh"
if [[ -f /root/.ssh/authorized_keys && ! -f "/home/$ADMIN_USER/.ssh/authorized_keys" ]]; then
  cp /root/.ssh/authorized_keys "/home/$ADMIN_USER/.ssh/authorized_keys"
  chown "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh/authorized_keys"
  chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys"
fi

install -d -m 0755 /etc/sudoers.d
sudoers="/etc/sudoers.d/$ADMIN_USER"
tmp=$(mktemp)
printf '%s\n' "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "$tmp"
visudo -cf "$tmp" >/dev/null
install -m 0440 "$tmp" "$sudoers"
rm -f "$tmp"
printf 'admin: ready: %s\n' "$ADMIN_USER"
