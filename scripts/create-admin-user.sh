#!/usr/bin/env bash
set -euo pipefail

# Idempotent provisioning of a non-root administrative user and SSH key.
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

ADMIN_KEY=${ADMIN_KEY:-}
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
  while true; do
    read -r -s -p "Initial password for $ADMIN_USER: " PASS1; printf '\n'
    read -r -s -p 'Confirm password: ' PASS2; printf '\n'
    [[ -n "$PASS1" && "$PASS1" == "$PASS2" ]] && break
    printf '%s\n' 'Passwords do not match or are empty.' >&2
  done
fi

USER_HOME=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
if [[ -z "$USER_HOME" ]]; then
  useradd -m -s /bin/bash "$ADMIN_USER"
  printf '%s:%s\n' "$ADMIN_USER" "$PASS1" | chpasswd
  unset PASS1 PASS2
  USER_HOME=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
fi

usermod -aG sudo "$ADMIN_USER"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || { printf 'admin: home directory not found for %s\n' "$ADMIN_USER" >&2; exit 1; }
SSH_DIR="$USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
install -d -m 0700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$SSH_DIR"

if [[ -z "$ADMIN_KEY" && ! -s "$AUTHORIZED_KEYS" ]]; then
  if [[ -f /root/.ssh/authorized_keys && -s /root/.ssh/authorized_keys ]]; then
    printf 'SSH public key for %s (Enter to copy root authorized keys): ' "$ADMIN_USER"
    read -r ADMIN_KEY
    if [[ -z "$ADMIN_KEY" ]]; then
      cat /root/.ssh/authorized_keys >> "$AUTHORIZED_KEYS"
    fi
  fi
fi

if [[ -z "$ADMIN_KEY" && ! -s "$AUTHORIZED_KEYS" ]]; then
  while true; do
    read -r -p "SSH public key for $ADMIN_USER: " ADMIN_KEY
    [[ "$ADMIN_KEY" =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521))\ [^[:space:]]+([[:space:]].*)?$ ]] && break
    printf '%s\n' 'Invalid SSH public key format.' >&2
  done
fi

if [[ -n "$ADMIN_KEY" ]]; then
  touch "$AUTHORIZED_KEYS"
  if ! grep -Fqx -- "$ADMIN_KEY" "$AUTHORIZED_KEYS"; then
    printf '%s\n' "$ADMIN_KEY" >> "$AUTHORIZED_KEYS"
  fi
fi

# StrictModes compatibility: OpenSSH must see the key file and directory as
# owned by the administrative account with restrictive permissions.
chown "$ADMIN_USER:$ADMIN_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"
[[ -e "$AUTHORIZED_KEYS" ]] || touch "$AUTHORIZED_KEYS"
chown "$ADMIN_USER:$ADMIN_USER" "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"

[[ -s "$AUTHORIZED_KEYS" ]] || {
  printf 'admin: no SSH public key is installed for %s\n' "$ADMIN_USER" >&2
  exit 1
}

install -d -m 0755 /etc/sudoers.d
sudoers="/etc/sudoers.d/$ADMIN_USER"
tmp=$(mktemp)
printf '%s\n' "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "$tmp"
visudo -cf "$tmp" >/dev/null
install -m 0440 "$tmp" "$sudoers"
rm -f "$tmp"
printf 'admin: ready: %s (SSH key installed)\n' "$ADMIN_USER"
