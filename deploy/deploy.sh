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
    --env-file) ENV_FILE=$2; shift 2;;
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
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates curl tar openssl ufw python3-venv
  "$ROOT/deploy/backup.sh" create >/dev/null || true
fi
[[ -x "$SING_BOX_BIN" ]] || "$ROOT/scripts/install-sing-box.sh"
if [[ "$DRY_RUN" == 0 ]]; then
  ADMIN_USER=${ADMIN_USER:?bootstrap must provide ADMIN_USER}
  ADMIN_USER="$ADMIN_USER" "$ROOT/scripts/create-admin-user.sh"
  "$ROOT/scripts/install-ssh-hardening.sh"
  [[ -x "$CLOUDFLARED_BIN" ]] || "$ROOT/scripts/install-cloudflared.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" "$ROOT/scripts/provision-cloudflare.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" "$ROOT/scripts/ensure-tls-certificate.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" "$ROOT/scripts/activate-multiprotocol.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" "$ROOT/scripts/apply-firewall.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" "$ROOT/scripts/generate-multiprotocol-clients.sh"
  systemctl --no-pager --quiet is-active sing-box.service
  systemctl --no-pager --quiet is-active cloudflared-echo.service
else
  if [[ -x "$CLOUDFLARED_BIN" ]]; then PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" DRY_RUN=1 "$ROOT/scripts/provision-cloudflare.sh"; fi
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" DRY_RUN=1 "$ROOT/scripts/activate-multiprotocol.sh"
  PROFILE="$PROFILE" RUNTIME_FILE="$ENV_FILE" DRY_RUN=1 "$ROOT/scripts/apply-firewall.sh"
fi
printf 'deploy: complete (profile=%s)\n' "$PROFILE"
