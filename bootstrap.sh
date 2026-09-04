#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROFILE=gateway
PROFILE_FILE="$ROOT/config/profiles/gateway.env.example"
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
SING_BOX_BIN=${SING_BOX_BIN:-/usr/local/bin/sing-box}
BASE_BOOTSTRAP_SCRIPT=${BASE_BOOTSTRAP_SCRIPT:-"$ROOT/bootstrap/01-base-packages.sh"}
SING_BOX_INSTALL_SCRIPT=${SING_BOX_INSTALL_SCRIPT:-"$ROOT/scripts/install-sing-box.sh"}
GENERATE_SCRIPT=${GENERATE_SCRIPT:-"$ROOT/scripts/generate-secrets.sh"}
VALIDATE_SCRIPT=${VALIDATE_SCRIPT:-"$ROOT/scripts/validate-secrets.sh"}
DETECT_SCRIPT=${DETECT_SCRIPT:-"$ROOT/scripts/detect-server-address.sh"}
DEPLOY_SCRIPT=${DEPLOY_SCRIPT:-"$ROOT/deploy/deploy.sh"}
TEST_MODE=${BOOTSTRAP_TEST_MODE:-0}

fail(){ printf 'bootstrap: %s\n' "$1" >&2; exit 1; }

[[ "$TEST_MODE" == 1 || "$(id -u)" == 0 ]] || fail 'root is required'
[[ -f /etc/debian_version ]] || fail 'Debian-based system required'
[[ -f "$PROFILE_FILE" ]] || fail "profile not found: $PROFILE_FILE"

set -a
source "$ROOT/config/defaults.env.example"
source "$PROFILE_FILE"
set +a

for file in "$BASE_BOOTSTRAP_SCRIPT" "$SING_BOX_INSTALL_SCRIPT" "$GENERATE_SCRIPT" "$VALIDATE_SCRIPT" "$DETECT_SCRIPT" "$DEPLOY_SCRIPT"; do
  [[ -f "$file" ]] || fail "required file missing: $file"
done

if [[ -f "$ROOT/config/versions.env.example" ]]; then set -a; source "$ROOT/config/versions.env.example"; set +a; fi
if [[ -f "$ROOT/config/versions.env" ]]; then set -a; source "$ROOT/config/versions.env"; set +a; fi

if [[ -f "$ROOT/config/packages.env" ]]; then
  printf '%s\n' 'bootstrap: installing base OS package profile'
  if [[ "$TEST_MODE" == 1 ]]; then
    printf '%s\n' 'bootstrap: base OS package installation skipped (test mode)'
  else
    "$BASE_BOOTSTRAP_SCRIPT"
  fi
fi

if [[ "$TEST_MODE" != 1 ]]; then
  missing=()
  for c in python3 curl tar openssl; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  command -v sshd >/dev/null 2>&1 || missing+=(sshd)
  if ((${#missing[@]})); then
    printf 'bootstrap: installing prerequisites: %s\n' "${missing[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates curl tar openssl openssh-server
  fi
fi

if [[ ! -x "$SING_BOX_BIN" ]]; then
  printf '%s\n' 'bootstrap: installing official sing-box'
  "$SING_BOX_INSTALL_SCRIPT"
fi

runtime_set_value(){
  local name=$1 value=$2 file=$3 tmp found=0
  tmp=$(mktemp "$(dirname "$file")/.vps-gateway-runtime.XXXXXX")
  trap 'rm -f "$tmp"' RETURN
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$name="* ]]; then
      printf '%s=%s\n' "$name" "$value" >> "$tmp"; found=1
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$file"
  [[ "$found" == 1 ]] || printf '%s=%s\n' "$name" "$value" >> "$tmp"
  chown root:root "$tmp" 2>/dev/null || true
  chmod 0600 "$tmp"
  mv "$tmp" "$file"
  trap - RETURN
}

prompt_value(){
  local __var=$1 label=$2 default=${3:-} value
  if [[ -n "$default" ]]; then read -r -p "$label [$default]: " value; value=${value:-$default}; else read -r -p "$label: " value; fi
  [[ -n "$value" ]] || fail "$__var is required"
  printf -v "$__var" '%s' "$value"
}

prompt_secret(){
  local __var=$1 label=$2 default=${3:-} value
  if [[ -n "$default" ]]; then read -r -s -p "$label [saved; Enter to reuse]: " value; printf '\n'; value=${value:-$default}; else read -r -s -p "$label: " value; printf '\n'; fi
  [[ -n "$value" ]] || fail "$__var is required"
  printf -v "$__var" '%s' "$value"
}

if [[ ! -f "$RUNTIME_FILE" ]]; then
  SOCKS_USERNAME=${SOCKS_USERNAME:-gateway}
  if [[ "$TEST_MODE" == 1 ]]; then
    SOCKS_USERNAME=${SOCKS_USERNAME:-gateway}
  elif [[ -t 0 ]]; then
    prompt_value SOCKS_USERNAME 'SOCKS/HTTP username' "$SOCKS_USERNAME"
  fi
  RUNTIME_FILE="$RUNTIME_FILE" CLIENT_INFO_FILE="$CLIENT_INFO_FILE" SING_BOX_BIN="$SING_BOX_BIN" \
    SOCKS_USERNAME="$SOCKS_USERNAME" SERVER_ADDRESS='' "$GENERATE_SCRIPT"
else
  printf 'bootstrap: preserving existing runtime credentials: %s\n' "$RUNTIME_FILE"
  if ! grep -q '^TRANSPORT_PASSWORD=' "$RUNTIME_FILE"; then
    runtime_set_value TRANSPORT_PASSWORD "$(openssl rand -hex 24)" "$RUNTIME_FILE"
  fi
fi

SSH_CURRENT_PORT=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}' || true)
SSH_PORT=${SSH_CURRENT_PORT:-${SSH_PORT:-22}}
runtime_set_value SSH_PORT "$SSH_PORT" "$RUNTIME_FILE"

# Interactive Cloudflare/TLS inputs are persisted in the protected runtime file.
# Existing values are reused; fresh installs prompt once.
for spec in \
  'CLOUDFLARE_API_TOKEN|Cloudflare API token|' \
  'CLOUDFLARE_ACCOUNT_ID|Cloudflare account ID|' \
  'CLOUDFLARE_ZONE_NAME|Cloudflare zone|engine.qzz.io' \
  'PUBLIC_HOSTNAME|Tunnel public hostname|echo.engine.qzz.io' \
  'DIRECT_HOSTNAME|Direct TLS hostname|direct.echo.engine.qzz.io' \
  'CLOUDFLARE_TUNNEL_NAME|Cloudflare Tunnel name|echo-gateway' \
  'CERTBOT_EMAIL|Let's Encrypt email|'; do
  IFS='|' read -r name label default <<< "$spec"
  current=''
  [[ -f "$RUNTIME_FILE" ]] && current=$(awk -F= -v n="$name" '$1==n{$1="";sub(/^=/,"");print;exit}' "$RUNTIME_FILE")
  if [[ -n "$current" ]]; then
    continue
  fi
  [[ "$TEST_MODE" == 1 ]] && continue
  case "$name" in
    CLOUDFLARE_API_TOKEN) prompt_secret "$name" "$label" '' ;;
    CERTBOT_EMAIL) prompt_value "$name" "$label" "$default" ;;
    *) prompt_value "$name" "$label" "$default" ;;
  esac
  runtime_set_value "$name" "${!name}" "$RUNTIME_FILE"
done

# Validate hostnames before deployment.
set -a; source "$RUNTIME_FILE"; source "$PROFILE_FILE"; set +a
fqdn_re='^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$'
[[ "$PUBLIC_HOSTNAME" =~ $fqdn_re && "$PUBLIC_HOSTNAME" == *".$CLOUDFLARE_ZONE_NAME" ]] || fail "PUBLIC_HOSTNAME must be a hostname under $CLOUDFLARE_ZONE_NAME"
[[ "$DIRECT_HOSTNAME" =~ $fqdn_re && "$DIRECT_HOSTNAME" == *".$CLOUDFLARE_ZONE_NAME" ]] || fail "DIRECT_HOSTNAME must be a hostname under $CLOUDFLARE_ZONE_NAME"
[[ "$CLOUDFLARE_TUNNEL_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || fail 'invalid Cloudflare Tunnel name'

printf '%s\n' 'bootstrap: validating gateway runtime'
PROFILE="$PROFILE" RUNTIME_FILE="$RUNTIME_FILE" CLIENT_INFO_FILE="$CLIENT_INFO_FILE" "$VALIDATE_SCRIPT"

printf '%s\n' 'bootstrap: running complete gateway deployment'
PROFILE="$PROFILE" RUNTIME_FILE="$RUNTIME_FILE" CLIENT_INFO_FILE="$CLIENT_INFO_FILE" \
  "$DEPLOY_SCRIPT" --env-file "$RUNTIME_FILE"

printf '%s\n' 'bootstrap: deployment complete'
