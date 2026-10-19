#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROFILE=gateway
PROFILE_FILE="$ROOT/config/profiles/gateway.env.example"
ENV_FILE=${ENV_FILE:-/root/vps-gateway-runtime.conf}
DRY_RUN=0
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift;;
    --env-file) [[ $# -ge 2 ]] || { printf 'deploy: --env-file needs a path\n' >&2; exit 2; }; ENV_FILE=$2; shift 2;;
    --env-file=*) ENV_FILE=${1#*=}; shift;;
    *) printf 'usage: %s [--dry-run] [--env-file PATH]\n' "$0" >&2; exit 2;;
  esac
done
fail(){ printf 'deploy: %s\n' "$1" >&2; exit 1; }
[[ -f "$PROFILE_FILE" ]] || fail 'comprehensive gateway profile not found'
[[ "$DRY_RUN" == 1 || $(id -u) == 0 ]] || fail 'root is required'
set -a
source "$ROOT/config/defaults.env.example"
source "$PROFILE_FILE"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
[[ -f "$ROOT/config/versions.env" ]] && source "$ROOT/config/versions.env"
set +a
printf 'deploy: profile=%s\n' "$PROFILE"
if [[ "$DRY_RUN" == 0 ]]; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates curl tar openssl ufw python3-venv openssh-server
  "$ROOT/deploy/backup.sh" create >/dev/null || true
fi
[[ -x "$SING_BOX_BIN" ]] || bash "$ROOT/scripts/install-sing-box.sh"
if [[ "$DRY_RUN" == 0 ]]; then
  ADMIN_USER=${ADMIN_USER:?bootstrap must provide ADMIN_USER}
  ADMIN_KEY=${ADMIN_KEY:-}
  ADMIN_USER="$ADMIN_USER" ADMIN_KEY="$ADMIN_KEY" bash "$ROOT/scripts/create-admin-user.sh"

  # First migrate the SSH listener, preserving root/password access and provider
  # firewall rules until the new admin-key connection has been verified.
  bash "$ROOT/scripts/migrate-ssh-port.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" RESET_UFW=0 bash "$ROOT/scripts/apply-firewall.sh"

  cat <<EOF
deploy: before SSH hardening, open a SECOND terminal on your workstation.
  1. Connect with the new administrator key: ssh -p 22 $ADMIN_USER@<VPS_ADDRESS>
  2. Run: sudo -k && sudo -n id -u
  3. Confirm that the second command prints 0.
Keep this root/VNC session open until the hardened SSH connection is verified.
EOF
  [[ -t 0 ]] || fail 'interactive confirmation is required; admin login has not been verified'
  read -r -p 'Did the separate admin-key SSH login and sudo test succeed? Type YES to continue: ' SSH_CONFIRM
  [[ "$SSH_CONFIRM" == YES ]] || fail 'SSH hardening cancelled; root/password policy has not been changed'

  SSH_ADMIN_LOGIN_VERIFIED=YES RUNTIME_FILE="$ENV_FILE" bash "$ROOT/scripts/install-ssh-hardening.sh"

  # The admin connection has been verified and the standardized SSH policy is
  # active. Now replace provider UFW rules with the declared gateway allow-list.
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" RESET_UFW=1 bash "$ROOT/scripts/apply-firewall.sh"

  [[ -x "$CLOUDFLARED_BIN" ]] || bash "$ROOT/scripts/install-cloudflared.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" bash "$ROOT/scripts/provision-cloudflare.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" bash "$ROOT/scripts/ensure-tls-certificate.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" bash "$ROOT/scripts/activate-multiprotocol.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" bash "$ROOT/scripts/generate-multiprotocol-clients.sh"
  systemctl --no-pager --quiet is-active sing-box.service
  systemctl --no-pager --quiet is-active cloudflared-echo.service
else
  if [[ -x "$CLOUDFLARED_BIN" ]]; then PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" DRY_RUN=1 bash "$ROOT/scripts/provision-cloudflare.sh"; fi
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" DRY_RUN=1 bash "$ROOT/scripts/activate-multiprotocol.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" RESET_UFW=1 DRY_RUN=1 bash "$ROOT/scripts/apply-firewall.sh"
fi
printf 'deploy: complete (profile=%s)\n' "$PROFILE"
