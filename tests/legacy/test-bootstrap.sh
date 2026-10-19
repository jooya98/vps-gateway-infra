#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

make_fake_sing_box() {
  local path=$1
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  generate)
    case "${2:-}" in
      uuid) printf '%s\n' '00000000-0000-4000-8000-000000000001' ;;
      reality-keypair) printf '%s\n' 'PrivateKey: test-bootstrap-private-key' 'PublicKey: test-bootstrap-public-key' ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
  chmod 0755 "$path"
}

make_fake_deploy() {
  local path=$1 log=$2
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$BOOTSTRAP_CALL_LOG"
EOF
  chmod 0755 "$path"
  : > "$log"
}

make_fake_systemctl() {
  local path=$1
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' active
EOF
  chmod 0755 "$path"
}

make_fake_detect() {
  local path=$1
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '198.51.100.10'
EOF
  chmod 0755 "$path"
}

run_bootstrap() {
  local profile=$1 runtime=$2 client=$3 binary=$4 deploy=$5 detect=$6 systemctl=$7
  RUNTIME_FILE="$runtime" \
  CLIENT_INFO_FILE="$client" \
  SING_BOX_BIN="$binary" \
  DEPLOY_SCRIPT="$deploy" \
  DETECT_SCRIPT="$detect" \
  SYSTEMCTL_BIN="$systemctl" \
  BOOTSTRAP_TEST_MODE=1 \
  BOOTSTRAP_CALL_LOG="$BOOTSTRAP_CALL_LOG" \
  "$ROOT/bootstrap.sh" --profile "$profile"
}

printf '%s\n' 'test-bootstrap: resilient first run generates, discovers, validates, deploys'
RUNTIME="$TMP/first-runtime.conf"
CLIENT="$TMP/first-client-info.txt"
BINARY="$TMP/first-sing-box"
DEPLOY="$TMP/first-deploy.sh"
DETECT="$TMP/first-detect.sh"
SYSTEMCTL="$TMP/first-systemctl"
CALL_LOG="$TMP/first-call.log"
make_fake_sing_box "$BINARY"
make_fake_deploy "$DEPLOY" "$CALL_LOG"
make_fake_detect "$DETECT"
make_fake_systemctl "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
first_output=$(run_bootstrap gateway-resilient "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$DETECT" "$SYSTEMCTL" 2>&1)
! grep -q 'test-bootstrap-private-key\|CLOUDFLARED' <<<"$first_output"
grep -q -- '--profile gateway-resilient --env-file ' "$CALL_LOG"
grep -q '^TRANSPORT_PASSWORD=' "$RUNTIME"
grep -q '^SNIPROXY_PUBLIC_IPV4=198.51.100.10$' "$RUNTIME"
! grep -q '^CLOUDFLARED_TUNNEL_TOKEN=' "$RUNTIME"
grep -q '^REALITY_PUBLIC_KEY=test-bootstrap-public-key$' "$CLIENT"
! grep -q 'REALITY_PRIVATE_KEY\|test-bootstrap-private-key' "$CLIENT"
[[ "$(stat -c '%a' "$RUNTIME")" == 600 ]]
[[ "$(stat -c '%a' "$CLIENT")" == 600 ]]
grep -q 'deployment status: success' <<<"$first_output"

printf '%s\n' 'test-bootstrap: existing resilient runtime is preserved'
EXISTING_RUNTIME="$TMP/existing-runtime.conf"
EXISTING_CLIENT="$TMP/existing-client-info.txt"
EXISTING_LOG="$TMP/existing-call.log"
cat > "$EXISTING_RUNTIME" <<'EOF'
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=existing-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=existing-socks-password
TRANSPORT_PASSWORD=existing-transport-password
SNIPROXY_PUBLIC_IPV4=198.51.100.11
EOF
cat > "$EXISTING_CLIENT" <<'EOF'
SERVER=
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=existing-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF
chmod 0600 "$EXISTING_RUNTIME" "$EXISTING_CLIENT"
cp "$EXISTING_RUNTIME" "$TMP/existing-before.conf"
EXISTING_DEPLOY="$TMP/existing-deploy.sh"
make_fake_deploy "$EXISTING_DEPLOY" "$EXISTING_LOG"
: > "$EXISTING_LOG"
BOOTSTRAP_CALL_LOG="$EXISTING_LOG"
existing_output=$(run_bootstrap gateway-resilient "$EXISTING_RUNTIME" "$EXISTING_CLIENT" "$BINARY" "$EXISTING_DEPLOY" "$DETECT" "$SYSTEMCTL" 2>&1)
cmp -s "$EXISTING_RUNTIME" "$TMP/existing-before.conf"
! grep -q 'Enter token' <<<"$existing_output"
grep -q -- '--profile gateway-resilient --env-file ' "$EXISTING_LOG"

printf '%s\n' 'test-bootstrap: minimal profile skips DNS discovery and Cloudflare prompt'
MIN_RUNTIME="$TMP/min-runtime.conf"
MIN_CLIENT="$TMP/min-client-info.txt"
MIN_LOG="$TMP/min-call.log"
MIN_DEPLOY="$TMP/min-deploy.sh"
make_fake_deploy "$MIN_DEPLOY" "$MIN_LOG"
BOOTSTRAP_CALL_LOG="$MIN_LOG"
min_output=$(run_bootstrap gateway-minimal "$MIN_RUNTIME" "$MIN_CLIENT" "$BINARY" "$MIN_DEPLOY" "$DETECT" "$SYSTEMCTL" 2>&1)
! grep -q 'Cloudflare tunnel token is required' <<<"$min_output"
! grep -q 'detecting public IPv4 for DNS steering' <<<"$min_output"
grep -q -- '--profile gateway-minimal --env-file ' "$MIN_LOG"
! grep -q '^SNIPROXY_PUBLIC_IPV4=' "$MIN_RUNTIME"

printf '%s\n' 'test-bootstrap: passed'
