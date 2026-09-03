#!/usr/bin/env bash

# create-admin-user.sh – Idempotent provisioning of a non-root administrative user.
# Run manually or invoke from the deployment workflow during initial bootstrap.

set -euo pipefail

if [[ "$(id -u)" != "0" ]]; then
  printf 'ERROR: This script must be run as root.\n' >&2
  exit 1
fi

ROOT_AUTH_KEYS="/root/.ssh/authorized_keys"

while true; do
  read -rp "Enter admin username: " ADMIN_USER
  if [[ "$ADMIN_USER" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    break
  fi
  printf 'Invalid username – use lowercase letters, digits, "-" or "_", starting with a letter.\n' >&2
done

TARGET_SSH_DIR="/home/$ADMIN_USER/.ssh"
TARGET_AUTH_KEYS="$TARGET_SSH_DIR/authorized_keys"
PASS1=''

if id "$ADMIN_USER" &>/dev/null; then
  printf 'User %s already exists – skipping password creation.\n' "$ADMIN_USER"
else
  while true; do
    read -rsp "Enter initial password for $ADMIN_USER: " PASS1
    printf '\n'
    read -rsp "Confirm password: " PASS2
    printf '\n'
    if [[ "$PASS1" == "$PASS2" && -n "$PASS1" ]]; then
      break
    fi
    printf 'Passwords do not match or empty – try again.\n' >&2
  done
fi

if id "$ADMIN_USER" &>/dev/null; then
  printf 'User %s already exists – ensuring home directory is present.\n' "$ADMIN_USER"
  if [[ ! -d "/home/$ADMIN_USER" ]]; then
    mkdir -p "/home/$ADMIN_USER"
    chown "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER"
  fi
else
  printf 'Creating user %s...\n' "$ADMIN_USER"
  useradd -m -s /bin/bash "$ADMIN_USER"
  printf '%s:%s\n' "$ADMIN_USER" "$PASS1" | chpasswd
fi

if groups "$ADMIN_USER" | grep -qw sudo; then
  printf 'User %s is already a member of sudo group.\n' "$ADMIN_USER"
else
  printf 'Adding %s to sudo group...\n' "$ADMIN_USER"
  usermod -aG sudo "$ADMIN_USER"
fi

if [[ ! -f "$ROOT_AUTH_KEYS" ]]; then
  printf 'WARNING: %s does not exist – skipping key copy.\n' "$ROOT_AUTH_KEYS" >&2
else
  mkdir -p "$TARGET_SSH_DIR"
  chmod 700 "$TARGET_SSH_DIR"

  if [[ -f "$TARGET_AUTH_KEYS" ]]; then
    printf 'Authorized keys already exist for %s. Overwrite? [y/N]: ' "$ADMIN_USER"
    read -r OVERWRITE
    if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
      cp "$ROOT_AUTH_KEYS" "$TARGET_AUTH_KEYS"
      printf 'Overwritten authorized_keys for %s.\n' "$ADMIN_USER"
    else
      printf 'Keeping existing authorized_keys for %s.\n' "$ADMIN_USER"
    fi
  else
    cp "$ROOT_AUTH_KEYS" "$TARGET_AUTH_KEYS"
    printf 'Copied authorized_keys to %s.\n' "$TARGET_AUTH_KEYS"
  fi

  chown "$ADMIN_USER:$ADMIN_USER" "$TARGET_AUTH_KEYS"
  chmod 600 "$TARGET_AUTH_KEYS"
fi

SUDOERS_DIR="/etc/sudoers.d"
SUDOERS_FILE="$SUDOERS_DIR/$ADMIN_USER"
SUDOERS_CONTENT="$ADMIN_USER ALL=(ALL) NOPASSWD:ALL"

mkdir -p "$SUDOERS_DIR"
TMP_SUDOERS="$(mktemp "$SUDOERS_DIR/${ADMIN_USER}.tmp.XXXX")"

if [[ -f "$SUDOERS_FILE" ]]; then
  cp -a "$SUDOERS_FILE" "$SUDOERS_FILE.bak.$(date +%s)"
fi

printf '%s\n' "$SUDOERS_CONTENT" > "$TMP_SUDOERS"

if visudo -cf "$TMP_SUDOERS"; then
  mv "$TMP_SUDOERS" "$SUDOERS_FILE"
  chmod 440 "$SUDOERS_FILE"
  printf 'Sudoers file %s installed successfully.\n' "$SUDOERS_FILE"
else
  printf 'ERROR: sudoers validation failed for %s\n' "$TMP_SUDOERS" >&2
  rm -f "$TMP_SUDOERS"
  exit 1
fi

printf '\nProvisioning complete.\n'
printf 'Validate with:\n'
printf '  id %s\n' "$ADMIN_USER"
printf '  groups %s\n' "$ADMIN_USER"
printf '  sudo -l -U %s\n' "$ADMIN_USER"
