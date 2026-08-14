#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

make_fake_sing_box() {
  local path=$1
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'PrivateKey: test-bootstrap-private-key' 'PublicKey: test-bootstrap-public-key'
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

run_bootstrap() {
  local runtime=$1 client=$2 binary=$3 deploy=$4 systemctl=$5
  RUNTIME_FILE="$runtime" \
  CLIENT_INFO_FILE="$client" \
  SING_BOX_BIN="$binary" \
  DEPLOY_SCRIPT="$deploy" \
  SYSTEMCTL_BIN="$systemctl" \
  BOOTSTRAP_TEST_MODE=1 \
  BOOTSTRAP_CALL_LOG="$BOOTSTRAP_CALL_LOG" \
  "$ROOT/bootstrap.sh" --profile gateway-minimal
}

printf '%s\n' 'test-bootstrap: first run generates, prompts, validates, deploys'
RUNTIME="$TMP/first-runtime.conf"
CLIENT="$TMP/first-client-info.txt"
BINARY="$TMP/first-sing-box"
DEPLOY="$TMP/first-deploy.sh"
SYSTEMCTL="$TMP/first-systemctl"
CALL_LOG="$TMP/first-call.log"
make_fake_sing_box "$BINARY"
make_fake_deploy "$DEPLOY" "$CALL_LOG"
make_fake_systemctl "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
first_output=$(printf '%s\n' 'test-bootstrap-cloudflare-token' | run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" 2>&1)
! grep -q 'test-bootstrap-private-key\|test-bootstrap-cloudflare-token' <<<"$first_output"
grep -q -- '--profile gateway-minimal --env-file ' "$CALL_LOG"
grep -q '^CLOUDFLARED_TUNNEL_TOKEN=test-bootstrap-cloudflare-token$' "$RUNTIME"
grep -q '^REALITY_PUBLIC_KEY=test-bootstrap-public-key$' "$CLIENT"
! grep -q 'REALITY_PRIVATE_KEY\|test-bootstrap-private-key' "$CLIENT"
[[ "$(stat -c '%a' "$RUNTIME")" == 600 ]]
[[ "$(stat -c '%a' "$CLIENT")" == 600 ]]
grep -q 'deployment status: success' <<<"$first_output"
grep -q 'client information:' <<<"$first_output"

printf '%s\n' 'test-bootstrap: existing runtime is preserved and token prompt is skipped'
EXISTING_RUNTIME="$TMP/existing-runtime.conf"
EXISTING_CLIENT="$TMP/existing-client-info.txt"
EXISTING_DEPLOY="$TMP/existing-deploy.sh"
EXISTING_LOG="$TMP/existing-call.log"
cat > "$EXISTING_RUNTIME" <<'EOF'
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=existing-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=existing-socks-password
CLOUDFLARED_TUNNEL_TOKEN=existing-cloudflare-token
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
cat > "$EXISTING_DEPLOY" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$BOOTSTRAP_CALL_LOG"
EOF
chmod 0755 "$EXISTING_DEPLOY"
: > "$EXISTING_LOG"
BOOTSTRAP_CALL_LOG="$EXISTING_LOG"
existing_output=$(run_bootstrap "$EXISTING_RUNTIME" "$EXISTING_CLIENT" "$BINARY" "$EXISTING_DEPLOY" "$SYSTEMCTL" 2>&1)
cmp -s "$EXISTING_RUNTIME" "$TMP/existing-before.conf"
! grep -q 'Enter token' <<<"$existing_output"
grep -q -- '--profile gateway-minimal --env-file ' "$EXISTING_LOG"

printf '%s\n' 'test-bootstrap: empty token is rejected before deployment'
EMPTY_RUNTIME="$TMP/empty-runtime.conf"
EMPTY_CLIENT="$TMP/empty-client-info.txt"
EMPTY_DEPLOY="$TMP/empty-deploy.sh"
EMPTY_LOG="$TMP/empty-call.log"
cp "$EXISTING_RUNTIME" "$EMPTY_RUNTIME"
python3 - "$EMPTY_RUNTIME" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
p.write_text(p.read_text().replace('CLOUDFLARED_TUNNEL_TOKEN=existing-cloudflare-token', 'CLOUDFLARED_TUNNEL_TOKEN='))
PY
cp "$EXISTING_CLIENT" "$EMPTY_CLIENT"
chmod 0600 "$EMPTY_RUNTIME" "$EMPTY_CLIENT"
make_fake_deploy "$EMPTY_DEPLOY" "$EMPTY_LOG"
: > "$EMPTY_LOG"
if empty_output=$(printf '\n' | BOOTSTRAP_CALL_LOG="$EMPTY_LOG" RUNTIME_FILE="$EMPTY_RUNTIME" CLIENT_INFO_FILE="$EMPTY_CLIENT" SING_BOX_BIN="$BINARY" DEPLOY_SCRIPT="$EMPTY_DEPLOY" SYSTEMCTL_BIN="$SYSTEMCTL" BOOTSTRAP_TEST_MODE=1 "$ROOT/bootstrap.sh" --profile gateway-minimal 2>&1); then
  printf 'test-bootstrap: empty token was accepted\n' >&2
  exit 1
fi
! grep -q 'test-bootstrap-cloudflare-token' <<<"$empty_output"
[[ ! -s "$EMPTY_LOG" ]]
printf '%s\n' 'test-bootstrap: passed'
