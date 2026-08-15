#!/usr/bin/env bash

# install‑ssh‑hardening.sh – Idempotent installer for the vps‑gateway SSH hardening drop‑in.
# Backs up any existing managed drop‑in, copies the generated config, validates with
# `sshd -t`, and reloads the sshd service. All steps abort on failure.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GENERATED="$ROOT/.generated/ssh/00-vps-gateway-hardening.conf"
DEST_DIR="/etc/ssh/sshd_config.d"
DEST="$DEST_DIR/00-vps-gateway-hardening.conf"

# ---------------------------------------------------------------------------
# Preconditions
if [[ "$(id -u)" != 0 ]]; then
  printf 'install‑ssh‑hardening: must be run as root\n' >&2
  exit 1
fi

if [[ ! -f $GENERATED ]]; then
  printf 'install‑ssh‑hardening: generated file not found: %s\n' "$GENERATED" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
# Initialise BACKUP to avoid unbound‑variable under set -u
BACKUP=""

# ---------------------------------------------------------------------------
# Backup existing managed drop‑in (if any)
if [[ -f $DEST ]]; then
  BACKUP="$DEST.bak.$(date +%s)"
  cp -a "$DEST" "$BACKUP"
  printf 'install‑ssh‑hardening: backup of existing drop‑in saved as %s\n' "$BACKUP"
fi

# ---------------------------------------------------------------------------
# Install new configuration (idempotent)
if cmp -s "$GENERATED" "$DEST" 2>/dev/null; then
  printf 'install‑ssh‑hardening: drop‑in already up‑to‑date, nothing to do\n'
else
  cp "$GENERATED" "$DEST"
  chmod 0644 "$DEST"
  printf 'install‑ssh‑hardening: installed new drop‑in %s\n' "$DEST"
fi

# ---------------------------------------------------------------------------
# Validate the resulting SSH config
if ! sshd -t; then
  printf 'install‑ssh‑hardening: configuration test failed – restoring backup\n' >&2
  if [[ -n $BACKUP ]]; then
    mv "$BACKUP" "$DEST"
    printf 'install‑ssh‑hardening: restored previous drop‑in\n'
  fi
  exit 1
fi

# ---------------------------------------------------------------------------
# Reload sshd (must succeed if systemctl is present)
if command -v systemctl >/dev/null 2>&1; then
  if systemctl reload sshd 2>/dev/null; then
    printf 'install‑ssh‑hardening: sshd service reloaded\n'
  elif systemctl reload ssh 2>/dev/null; then
    printf 'install‑ssh‑hardening: ssh service reloaded\n'
  else
    printf 'install‑ssh‑hardening: FAILED to reload sshd/ssh service\n' >&2
    exit 1
  fi
fi

exit 0
