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

# Load non-secret profile flags before deciding which runtime inputs are needed.
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

# Load only non-secret version settings before installing sing-box.
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
  if ((${#missing_prerequisites[@]})); then
    printf 'bootstrap: installing missing pre-generation prerequisites: %s\n' "${missing_prerequisites[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ca-certificates curl tar openssl
  fi
fi

if [[ ! -x "$SING_BOX_BIN" ]]; then
  printf '%s\n' 'bootstrap: installing official sing-box before credential generation'
  "$SING_BOX_INSTALL_SCRIPT"
fi

if [[ ! -f "$RUNTIME_FILE" ]]; then
  printf '%s\n' 'bootstrap: generating new gateway credentials'
  RUNTIME_FILE="$RUNTIME_FILE" CLIENT_INFO_FILE="$CLIENT_INFO_FILE" SING_BOX_BIN="$SING_BOX_BIN" \
    "$GENERATE_SCRIPT"
else
  printf '%s\n' "bootstrap: preserving existing runtime credentials: $RUNTIME_FILE"
fi

# External credentials are prompted only when the selected profile actually enables them.
if [[ "${ENABLE_CLOUDFLARED:-false}" == true ]]; then
  cloudflare_token_present=0
  if [[ -f "$RUNTIME_FILE" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == CLOUDFLARED_TUNNEL_TOKEN=* && -n "${line#*=}" ]]; then
        cloudflare_token_present=1
        break
      fi
    done < "$RUNTIME_FILE"
  fi

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

    runtime_tmp=$(mktemp "$(dirname "$RUNTIME_FILE")/.vps-gateway-runtime.XXXXXX")
    cleanup_runtime_tmp() { rm -f "$runtime_tmp"; }
    trap cleanup_runtime_tmp EXIT
    token_line_found=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == CLOUDFLARED_TUNNEL_TOKEN=* ]]; then
        printf 'CLOUDFLARED_TUNNEL_TOKEN=%s\n' "$CLOUDFLARED_TUNNEL_TOKEN" >> "$runtime_tmp"
        token_line_found=1
      else
        printf '%s\n' "$line" >> "$runtime_tmp"
      fi
    done < "$RUNTIME_FILE"
    if [[ "$token_line_found" == 0 ]]; then
      printf 'CLOUDFLARED_TUNNEL_TOKEN=%s\n' "$CLOUDFLARED_TUNNEL_TOKEN" >> "$runtime_tmp"
    fi
    if [[ "$(id -u)" == 0 ]]; then
      chown root:root "$runtime_tmp"
    fi
    chmod 0600 "$runtime_tmp"
    mv "$runtime_tmp" "$RUNTIME_FILE"
    unset CLOUDFLARED_TUNNEL_TOKEN
    trap - EXIT
    printf '%s\n' 'bootstrap: Cloudflare tunnel token stored in protected runtime file'
  else
    printf '%s\n' 'bootstrap: existing Cloudflare tunnel token detected; prompt skipped'
  fi
else
  printf '%s\n' 'bootstrap: Cloudflare tunnel disabled by profile; token input skipped'
fi

printf '%s\n' 'bootstrap: validating runtime credentials'
PROFILE="$PROFILE" RUNTIME_FILE="$RUNTIME_FILE" CLIENT_INFO_FILE="$CLIENT_INFO_FILE" "$VALIDATE_SCRIPT"

if [[ "${ENABLE_DNS_STEERING:-false}" == true ]]; then
  printf '%s\n' 'bootstrap: detecting public IPv4 for DNS steering'
  SERVER_IPV4=$(SERVER_ADDRESS_MODE=ipv4 SERVER_ADDRESS_PREFERENCE=ipv4 "$DETECT_SCRIPT")
  [[ -n "$SERVER_IPV4" ]] || {
    printf '%s\n' 'bootstrap: public IPv4 detection returned an empty value' >&2
    exit 1
  }

  runtime_tmp=$(mktemp "$(dirname "$RUNTIME_FILE")/.vps-gateway-runtime.XXXXXX")
  cleanup_runtime_tmp() { rm -f "$runtime_tmp"; }
  trap cleanup_runtime_tmp EXIT
  ipv4_line_found=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == SNIPROXY_PUBLIC_IPV4=* ]]; then
      printf 'SNIPROXY_PUBLIC_IPV4=%s\n' "$SERVER_IPV4" >> "$runtime_tmp"
      ipv4_line_found=1
    else
      printf '%s\n' "$line" >> "$runtime_tmp"
    fi
  done < "$RUNTIME_FILE"
  if [[ "$ipv4_line_found" == 0 ]]; then
    printf 'SNIPROXY_PUBLIC_IPV4=%s\n' "$SERVER_IPV4" >> "$runtime_tmp"
  fi
  if [[ "$(id -u)" == 0 ]]; then
    chown root:root "$runtime_tmp"
  fi
  chmod 0600 "$runtime_tmp"
  mv "$runtime_tmp" "$RUNTIME_FILE"
  trap - EXIT
  printf 'bootstrap: discovered public IPv4: %s\n' "$SERVER_IPV4"
fi

printf '%s\n' 'bootstrap: validating completed runtime configuration'
PROFILE="$PROFILE" RUNTIME_FILE="$RUNTIME_FILE" CLIENT_INFO_FILE="$CLIENT_INFO_FILE" "$VALIDATE_SCRIPT"

printf '%s\n' 'bootstrap: detecting client-facing server address'
SERVER_ADDRESS=$("$DETECT_SCRIPT")

client_info_tmp=$(mktemp "$(dirname "$CLIENT_INFO_FILE")/.vps-gateway-client-info.XXXXXX")
cleanup_client_info_tmp() { rm -f "$client_info_tmp"; }
trap cleanup_client_info_tmp EXIT

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == SERVER=* ]]; then
    printf 'SERVER=%s\n' "$SERVER_ADDRESS" >> "$client_info_tmp"
  else
    printf '%s\n' "$line" >> "$client_info_tmp"
  fi
done < "$CLIENT_INFO_FILE"

if [[ "$(id -u)" == 0 ]]; then
  chown root:root "$client_info_tmp"
fi
chmod 0600 "$client_info_tmp"
mv "$client_info_tmp" "$CLIENT_INFO_FILE"
trap - EXIT

printf '%s\n' 'bootstrap: starting gateway deployment'
"$DEPLOY_SCRIPT" --profile "$PROFILE" --env-file "$RUNTIME_FILE"

printf '%s\n' 'bootstrap: deployment status: success'
if command -v "$SYSTEMCTL_BIN" >/dev/null 2>&1; then
  for service in sing-box.service cloudflared.service; do
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
