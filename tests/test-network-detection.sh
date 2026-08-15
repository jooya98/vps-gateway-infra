#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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

printf '%s\n' 'test-network-detection: IPv4 detection'
RUNTIME="$TMP/runtime.conf"
CLIENT="$TMP/client-info.txt"
BINARY="$TMP/sing-box"
DEPLOY="$TMP/deploy.sh"
SYSTEMCTL="$TMP/systemctl"
CALL_LOG="$TMP/call.log"
cat > "$RUNTIME" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
EOF
cat > "$CLIENT" <<EOF
SERVER=
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=test-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF
make_fake_deploy "$DEPLOY" "$CALL_LOG"
cat > "$SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' active
EOF
chmod 0755 "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
first_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" 2>&1)

printf '%s\n' 'test-network-detection: IPv6 detection'
RUNTIME="$TMP/runtime-ipv6.conf"
CLIENT="$TMP/client-ipv6.txt"
DEPLOY="$TMP/deploy-ipv6.sh"
CALL_LOG="$TMP/call-ipv6.log"
cp "$RUNTIME" "$RUNTIME"
python3 - "$RUNTIME" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
p.write_text(p.read_text().replace('SERVER_ADDRESS_MODE=auto', 'SERVER_ADDRESS_MODE=ipv6'))
PY
cp "$CLIENT" "$CLIENT"
python3 - "$CLIENT" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
p.write_text(p.read_text().replace('SERVER=70.34.204.80', 'SERVER=2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a'))
PY
make_fake_deploy "$DEPLOY" "$CALL_LOG"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
ipv6_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" 2>&1)

printf '%s\n' 'test-network-detection: preference handling'
RUNTIME="$TMP/runtime-pref.conf"
CLIENT="$TMP/client-pref.txt"
DEPLOY="$TMP/deploy-pref.sh"
CALL_LOG="$TMP/call-pref.log"
cp "$RUNTIME" "$RUNTIME"
python3 - "$RUNTIME" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
p.write_text(p.read_text().replace('SERVER_ADDRESS_MODE=auto', 'SERVER_ADDRESS_MODE=auto\nSERVER_ADDRESS_PREFERENCE=ipv6'))
PY
cp "$CLIENT" "$CLIENT"
python3 - "$CLIENT" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
p.write_text(p.read_text().replace('SERVER=70.34.204.80', 'SERVER=2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a'))
PY
make_fake_deploy "$DEPLOY" "$CALL_LOG"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
pref_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" 2>&1)

printf '%s\n' 'test-network-detection: failure when no public address exists'
RUNTIME="$TMP/runtime-fail.conf"
CLIENT="$TMP/client-fail.txt"
DEPLOY="$TMP/deploy-fail.sh"
CALL_LOG="$TMP/call-fail.log"
cp "$RUNTIME" "$RUNTIME"
python3 - "$RUNTIME" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
p.write_text(p.read_text().replace('SERVER_ADDRESS_MODE=auto', 'SERVER_ADDRESS_MODE=ipv4'))
PY
cp "$CLIENT" "$CLIENT"
python3 - "$CLIENT" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
p.write_text(p.read_text().replace('SERVER=70.34.204.80', 'SERVER='))
PY
make_fake_deploy "$DEPLOY" "$CALL_LOG"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
if fail_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" 2>&1); then
  printf 'test-network-detection: no public address was detected\n' >&2
  exit 1
fi

printf '%s\n' 'test-network-detection: passed'