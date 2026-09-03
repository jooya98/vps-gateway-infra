#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROFILE=${PROFILE:-gateway-minimal}
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
SING_BOX_BIN=${SING_BOX_BIN:-/usr/local/bin/sing-box}
BASE_BOOTSTRAP_SCRIPT=${BASE_BOOTSTRAP_SCRIPT:-"$ROOT/bootstrap/01-base-packages.sh"}
SING_BOX_INSTALL_SCRIPT=${SING_BOX_INSTALL_SCRIPT:-"$ROOT/scripts/install-sing-box.sh"}
GENERATE_SCRIPT=${GENERATE_SCRIPT:-"$ROOT/scripts/generate-secrets.sh"}
VALIDATE_SCRIPT=${VALIDATE_SCRIPT:-"$ROOT/scripts/validate-secrets.sh"}
DETECT_SCRIPT=${DETECT_SCRIPT:-"$ROOT/scripts/detect-server-address.sh"}
DEPLOY_SCRIPT=${DEPLOY_SCRIPT:-"$ROOT/deploy/deploy.sh"}
SYSTEMCTL_BIN=${SYSTEMCTL_BIN:-systemctl}
TEST_MODE=${BOOTSTRAP_TEST_MODE:-0}

usage() {
  printf '%s\n' "usage: $0 [--profile NAME]"
}

while (($#)); do
  case "$1" in
    --profile)
      (($# >= 2)) || { printf 'bootstrap: --profile requires a value\n' >&2; exit 2; }
      PROFILE=$2
      shift 2
      ;;
    --profile=*)
      PROFILE=${1#*=}
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'bootstrap: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$TEST_MODE" != 1 && "$(id -u)" != 0 ]]; then
  printf 'bootstrap: root is required\n' >&2
  exit 1
fi
[[ -f /etc/debian_version ]] || {
  printf 'bootstrap: Debian-based system required (/etc/debian_version missing)\n' >&2
  exit 1
}
[[ "$PROFILE" =~ ^[A-Za-z0-9_-]+$ ]] || {
  printf 'bootstrap: invalid profile name\n' >&2
  exit 1
}

PROFILE_FILE="$ROOT/config/profiles/$PROFILE.env.example"
[[ -f "$PROFILE_FILE" ]] || {
  printf 'bootstrap: profile not found: %s\n' "$PROFILE" >&2
  exit 1
}

set -a
# shellcheck disable=SC1091
source "$ROOT/config/defaults.env.example"
# shellcheck disable=SC1091
source "$PROFILE_FILE"
set +a

required_files=(
  "$BASE_BOOTSTRAP_SCRIPT"
  "$SING_BOX_INSTALL_SCRIPT"
  "$GENERATE_SCRIPT"
  "$VALIDATE_SCRIPT"
  "$DETECT_SCRIPT"
  "$DEPLOY_SCRIPT"
)
for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || { printf 'bootstrap: required file missing: %s\n' "$file" >&2; exit 1; }
done

if [[ -f "$ROOT/config/versions.env.example" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/config/versions.env.example"
  set +a
fi
if [[ -f "$ROOT/config/versions.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/config/versions.env"
  set +a
fi

if [[ -f "$ROOT/config/packages.env" ]]; then
  printf '%s\n' 'bootstrap: installing configured base OS package profile'
  if [[ "$TEST_MODE" == 1 ]]; then
    printf '%s\n' 'bootstrap: base OS package installation skipped (test mode)'
  else
    "$BASE_BOOTSTRAP_SCRIPT"
  fi
else
  printf '%s\n' 'bootstrap: config/packages.env not present; base OS package layer skipped'
fi

if [[ "$TEST_MODE" != 1 ]]; then
  missing_prerequisites=()
  for command_name in python3 curl tar openssl; do
    command -v "$command_name" >/dev/null 2>&1 || missing_prerequisites+=("$command_name")
  done
  if ! command -v sshd >/dev/null 2>&1; then
    missing_prerequisites+=(sshd)
  fi
  if ((${#missing_prerequisites[@]})); then
    printf 'bootstrap: installing missing prerequisites: %s\n' "${missing_prerequisites[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates curl tar openssl openssh-server
  fi
fi

if [[ ! -x "$SING_BOX_BIN" ]]; then
  printf '%s\n' 'bootstrap: installing official sing-box before credential generation'
  "$SING_BOX_INSTALL_SCRIPT"
fi

# Preserve the effective SSH listener before any hardening changes are applied.
SSH_CURRENT_PORT=$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2; exit }' || true)
if [[ -n "$SSH_CURRENT_PORT" && "$SSH_CURRENT_PORT" =~ ^[0-9]+$ ]]; then
  SSH_PORT=$SSH_CURRENT_PORT
else
  SSH_PORT=${SSH_PORT:-22}
fi

runtime_set_value() {
  local name=$1 value=$2 file=$3 tmp found=0
  tmp=$(mktemp "$(dirname "$file")/.vps-gateway-runtime.XXXXXX")
  trap 'rm -f "$tmp"' RETURN
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$name="* ]]; then
      printf '%s=%s\n' "$name" "$value" >> "$tmp"
      found=1
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$file"
  if [[ "$found" == 0 ]]; then
    printf '%s=%s\n' "$name" "$value" >> "$tmp"
  fi
  if [[ "$(id -u)" == 0 ]]; then
    chown root:root "$tmp"
  fi
  chmod 0600 "$tmp"
  mv "$tmp" "$file"
  trap - RETURN
}

if [[ ! -f "$RUNTIME_FILE" ]]; then
  printf '%s\n' 'bootstrap: generating new gateway credentials'
  RUNTIME_FILE="$RUNTIME_FILE" CLIENT_INFO_FILE="$CLIENT_INFO_FILE" SING_BOX_BIN="$SING_BOX_BIN" \
    SOCKS_USERNAME="${SOCKS_USERNAME:-gateway}" SERVER_ADDRESS="" \
    "$GENERATE_SCRIPT"
else
  printf '%s\n' "bootstrap: preserving existing runtime credentials: $RUNTIME_FILE"
  # Older runtime files may predate transport credentials. Add only the missing
  # derived secret; never rotate an existing credential implicitly.
  if ! grep -q '^TRANSPORT_PASSWORD=' "$RUNTIME_FILE"; then
    TRANSPORT_PASSWORD=$(openssl rand -hex 24)
    runtime_set_value TRANSPORT_PASSWORD "$TRANSPORT_PASSWORD" "$RUNTIME_FILE"
    printf '%s\n' 'bootstrap: added missing transport credential to existing runtime'
  fi
fi

runtime_set_value SSH_PORT "$SSH_PORT" "$RUNTIME_FILE"

if [[ "${ENABLE_CLOUDFLARED:-false}" == true ]]; then
  cloudflare_token_present=0
  while IFS= read -r line; do
    if [[ "$line" == CLOUDFLARED_TUNNEL_TOKEN=* && -n "${line#*=}" ]]; then
      cloudflare_token_present=1
      break
    fi
  done < "$RUNTIME_FILE"

  if [[ "$cloudflare_token_present" == 0 ]]; then
    printf '%s\n' 'Cloudflare tunnel token is required for this profile.' >&2
    printf 'Enter token (input hidden): ' >&2
    if ! IFS= read -r -s CLOUDFLARED_TUNNEL_TOKEN; then
      unset CLOUDFLARED_TUNNEL_TOKEN
      printf '\nbootstrap: unable to read Cloudflare tunnel token\n' >&2
      exit 1
    fi
    printf '\n' >&2
    [[ -n "$CLOUDFLARED_TUNNEL_TOKEN" ]] || {
      unset CLOUDFLARED_TUNNEL_TOKEN
      printf 'bootstrap: Cloudflare tunnel token cannot be empty\n' >&2
      exit 1
    }
    runtime_set_value CLOUDFLARED_TUNNEL_TOKEN "$CLOUDFLARED_TUNNEL_TOKEN" "$RUNTIME_FILE"
    unset CLOUDFLARED_TUNNEL_TOKEN
    printf '%s\n' 'bootstrap: Cloudflare tunnel token stored in protected runtime file'
  else
    printf '%s\n' 'bootstrap: existing Cloudflare tunnel token detected; prompt skipped'
  fi
else
  printf '%s\n' 'bootstrap: Cloudflare tunnel disabled by profile; token input skipped'
fi

if [[ "${ENABLE_DNS_STEERING:-false}" == true ]]; then
  printf '%s\n' 'bootstrap: detecting public IPv4 for DNS steering'
  SERVER_IPV4=$(SERVER_ADDRESS_MODE=ipv4 SERVER_ADDRESS_PREFERENCE=ipv4 "$DETECT_SCRIPT")
  [[ -n "$SERVER_IPV4" ]] || {
    printf '%s\n' 'bootstrap: public IPv4 detection returned an empty value' >&2
    exit 1
  }
  runtime_set_value SNIPROXY_PUBLIC_IPV4 "$SERVER_IPV4" "$RUNTIME_FILE"
  printf 'bootstrap: discovered public IPv4: %s\n' "$SERVER_IPV4"
else
  printf '%s\n' 'bootstrap: DNS steering disabled by profile; public IPv4 discovery for sniproxy skipped'
fi

printf '%s\n' 'bootstrap: validating completed runtime configuration'
PROFILE="$PROFILE" RUNTIME_FILE="$RUNTIME_FILE" CLIENT_INFO_FILE="$CLIENT_INFO_FILE" "$VALIDATE_SCRIPT"

printf '%s\n' 'bootstrap: detecting client-facing server address'
SERVER_ADDRESS=$(SERVER_ADDRESS_PREFERENCE=ipv4 "$DETECT_SCRIPT")

client_info_tmp=$(mktemp "$(dirname "$CLIENT_INFO_FILE")/.vps-gateway-client-info.XXXXXX")
cleanup_client_info_tmp() { rm -f "$client_info_tmp"; }
trap cleanup_client_info_tmp EXIT

while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    SERVER=*) printf 'SERVER=%s\n' "$SERVER_ADDRESS" >> "$client_info_tmp" ;;
    PORT=*) printf 'PORT=%s\n' "$VLESS_PORT" >> "$client_info_tmp" ;;
    *) printf '%s\n' "$line" >> "$client_info_tmp" ;;
  esac
done < "$CLIENT_INFO_FILE"

if [[ "$(id -u)" == 0 ]]; then
  chown root:root "$client_info_tmp"
fi
chmod 0600 "$client_info_tmp"
mv "$client_info_tmp" "$CLIENT_INFO_FILE"
trap - EXIT

printf '%s\n' 'bootstrap: starting gateway deployment'
SSH_PORT="$SSH_PORT" PROFILE="$PROFILE" "$DEPLOY_SCRIPT" --profile "$PROFILE" --env-file "$RUNTIME_FILE"

printf '%s\n' 'bootstrap: deployment status: success'
if command -v "$SYSTEMCTL_BIN" >/dev/null 2>&1; then
  for service in sing-box.service cloudflared.service sniproxy.service; do
    state=$(
      "$SYSTEMCTL_BIN" is-active "$service" 2>/dev/null || true
    )
    [[ -n "$state" ]] || state=unknown
    printf 'bootstrap: service %-24s %s\n' "$service" "$state"
  done
else
  printf '%s\n' 'bootstrap: service status summary unavailable (systemctl not found)'
fi
printf 'bootstrap: client information: %s\n' "$CLIENT_INFO_FILE"
