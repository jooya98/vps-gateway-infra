#!/usr/bin/env bash
set -euo pipefail

fail(){ printf 'cloudflared-installer: %s\n' "$1" >&2; exit 1; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET="$ROOT/scripts/activate-cloudflared-local.sh"
INPUT_FILE=${INPUT_FILE:-/root/vps-gateway-cloudflare-input.conf}

[[ $EUID -eq 0 ]] || fail 'root is required'
[[ -x /usr/bin/env ]] || fail 'env is required'
[[ -f "$TARGET" ]] || fail 'activate-cloudflared-local.sh not found'
[[ -t 0 ]] || fail 'interactive installation requires a TTY'

saved_token=''
saved_account=''
saved_zone=''
saved_host=''
saved_tunnel=''
if [[ -f "$INPUT_FILE" ]]; then
  set -a
  source "$INPUT_FILE"
  set +a
  saved_token=${CLOUDFLARE_API_TOKEN:-}
  saved_account=${CLOUDFLARE_ACCOUNT_ID:-}
  saved_zone=${CLOUDFLARE_ZONE_NAME:-}
  saved_host=${PUBLIC_HOSTNAME:-}
  saved_tunnel=${CLOUDFLARE_TUNNEL_NAME:-}
fi

prompt_value(){
  local __var=$1 label=$2 default=${3:-} value
  if [[ -n "$default" ]]; then
    read -r -p "$label [$default]: " value
    value=${value:-$default}
  else
    read -r -p "$label: " value
  fi
  [[ -n "$value" ]] || fail "$__var is required"
  printf -v "$__var" '%s' "$value"
}

prompt_secret(){
  local __var=$1 label=$2 has_saved=$3 value
  if [[ "$has_saved" == 1 ]]; then
    read -r -s -p "$label [saved; Enter to reuse]: " value
    printf '\n'
    value=${value:-$saved_token}
  else
    read -r -s -p "$label: " value
    printf '\n'
  fi
  [[ -n "$value" ]] || fail "$__var is required"
  printf -v "$__var" '%s' "$value"
}

prompt_secret CLOUDFLARE_API_TOKEN 'Cloudflare API token' "$([[ -n "$saved_token" ]] && echo 1 || echo 0)"
prompt_value CLOUDFLARE_ACCOUNT_ID 'Cloudflare account ID' "$saved_account"
prompt_value CLOUDFLARE_ZONE_NAME 'Cloudflare zone' "${saved_zone:-engine.qzz.io}"
prompt_value PUBLIC_HOSTNAME 'Public hostname for the Tunnel' "${saved_host:-echo.engine.qzz.io}"
prompt_value CLOUDFLARE_TUNNEL_NAME 'Cloudflare Tunnel name' "${saved_tunnel:-echo-gateway}"

install -d -m 0700 "$(dirname "$INPUT_FILE")"
umask 077
cat > "$INPUT_FILE" <<EOF
# Cloudflare installer inputs. Root-only; do not commit or share.
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID=$CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_ZONE_NAME=$CLOUDFLARE_ZONE_NAME
PUBLIC_HOSTNAME=$PUBLIC_HOSTNAME
CLOUDFLARE_TUNNEL_NAME=$CLOUDFLARE_TUNNEL_NAME
EOF
chmod 0600 "$INPUT_FILE"

export CLOUDFLARE_API_TOKEN
export CLOUDFLARE_ACCOUNT_ID
export CLOUDFLARE_ZONE_NAME
export PUBLIC_HOSTNAME
export CLOUDFLARE_TUNNEL_NAME

printf '\ncloudflared-installer: configuration collected; invoking local-managed provisioning...\n\n'
exec bash "$TARGET"
