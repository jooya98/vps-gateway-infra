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

make_fake_detect() {
  local path=$1 address=$2
  cat > "$path" <<EOF
#!/usr/bin/env bash
if [[ -z "$address" ]]; then
  echo "detect-server-address: no public IPv4 or IPv6 address found" >&2
  exit 1
fi
printf '%s\n' "$address"
EOF
  chmod 0755 "$path"
}

make_fake_sing_box() {
  local path=$1
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod 0755 "$path"
}

run_bootstrap() {
  local runtime=$1 client=$2 binary=$3 deploy=$4 systemctl=$5 detect=$6
  RUNTIME_FILE="$runtime" \
  CLIENT_INFO_FILE="$client" \
  SING_BOX_BIN="$binary" \
  DEPLOY_SCRIPT="$deploy" \
  DETECT_SCRIPT="$detect" \
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
DETECT="$TMP/detect-ipv4.sh"
CALL_LOG="$TMP/call.log"
cat > "$RUNTIME" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
SERVER_ADDRESS_MODE=auto
SERVER_ADDRESS_PREFERENCE=ipv4
EOF
chmod 600 "$RUNTIME"
cat > "$CLIENT" <<EOF
SERVER=
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=test-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF
chmod 600 "$CLIENT"
make_fake_deploy "$DEPLOY" "$CALL_LOG"
make_fake_detect "$DETECT" "192.0.2.1"
make_fake_sing_box "$BINARY"
cat > "$SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' active
EOF
chmod 0755 "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
first_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" "$DETECT" 2>&1)

printf '%s\n' 'test-network-detection: IPv6 detection'
RUNTIME="$TMP/runtime-ipv6.conf"
CLIENT="$TMP/client-ipv6.txt"
DEPLOY="$TMP/deploy-ipv6.sh"
SYSTEMCTL="$TMP/systemctl-ipv6"
DETECT="$TMP/detect-ipv6.sh"
CALL_LOG="$TMP/call-ipv6.log"
cp /dev/null "$RUNTIME"
cat > "$RUNTIME" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
SERVER_ADDRESS_MODE=ipv6
EOF
cat > "$CLIENT" <<EOF
SERVER=2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=test-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF
chmod 600 "$RUNTIME"
chmod 600 "$CLIENT"
make_fake_deploy "$DEPLOY" "$CALL_LOG"
make_fake_detect "$DETECT" "2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a"
make_fake_sing_box "$BINARY"
cat > "$SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' active
EOF
chmod 0755 "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
ipv6_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" "$DETECT" 2>&1)

printf '%s\n' 'test-network-detection: preference handling'
RUNTIME="$TMP/runtime-pref.conf"
CLIENT="$TMP/client-pref.txt"
DEPLOY="$TMP/deploy-pref.sh"
SYSTEMCTL="$TMP/systemctl-pref"
DETECT="$TMP/detect-pref.sh"
CALL_LOG="$TMP/call-pref.log"
cat > "$RUNTIME" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
SERVER_ADDRESS_MODE=auto
SERVER_ADDRESS_PREFERENCE=ipv6
EOF
cat > "$CLIENT" <<EOF
SERVER=2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=test-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF
chmod 600 "$RUNTIME"
chmod 600 "$CLIENT"
make_fake_deploy "$DEPLOY" "$CALL_LOG"
make_fake_detect "$DETECT" "2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a"
make_fake_sing_box "$BINARY"
cat > "$SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' active
EOF
chmod 0755 "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
pref_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" "$DETECT" 2>&1)

printf '%s\n' 'test-network-detection: failure when no public address exists'
RUNTIME="$TMP/runtime-fail.conf"
CLIENT="$TMP/client-fail.txt"
DEPLOY="$TMP/deploy-fail.sh"
SYSTEMCTL="$TMP/systemctl-fail"
DETECT="$TMP/detect-fail.sh"
CALL_LOG="$TMP/call-fail.log"
cat > "$RUNTIME" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
SERVER_ADDRESS_MODE=ipv4
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
chmod 600 "$RUNTIME"
chmod 600 "$CLIENT"
make_fake_deploy "$DEPLOY" "$CALL_LOG"
make_fake_detect "$DETECT" ""
make_fake_sing_box "$BINARY"
cat > "$SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' active
EOF
chmod 0755 "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
if fail_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" "$DETECT" 2>&1); then
  printf 'test-network-detection: no public address was detected\n' >&2
  exit 1
fi

printf '%s\n' 'test-network-detection: IPv4 + IPv6 regression'
RUNTIME="$TMP/runtime-dual.conf"
CLIENT="$TMP/client-dual.txt"
DEPLOY="$TMP/deploy-dual.sh"
SYSTEMCTL="$TMP/systemctl-dual"
DETECT="$TMP/detect-dual.sh"
CALL_LOG="$TMP/call-dual.log"
cat > "$RUNTIME" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
SERVER_ADDRESS_MODE=auto
SERVER_ADDRESS_PREFERENCE=ipv4
EOF
cat > "$CLIENT" <<EOF
SERVER=2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=test-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF
chmod 600 "$RUNTIME"
chmod 600 "$CLIENT"
make_fake_deploy "$DEPLOY" "$CALL_LOG"
make_fake_detect "$DETECT" "192.0.2.1"
make_fake_sing_box "$BINARY"
cat > "$SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' active
EOF
chmod 0755 "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
dual_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" "$DETECT" 2>&1)

printf '%s\n' 'test-network-detection: IPv6 explicit regression'
RUNTIME="$TMP/runtime-ipv6-explicit.conf"
CLIENT="$TMP/client-ipv6-explicit.txt"
DEPLOY="$TMP/deploy-ipv6-explicit.sh"
SYSTEMCTL="$TMP/systemctl-ipv6-explicit"
DETECT="$TMP/detect-ipv6-explicit.sh"
CALL_LOG="$TMP/call-ipv6-explicit.log"
cat > "$RUNTIME" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
SERVER_ADDRESS_MODE=ipv6
EOF
cat > "$CLIENT" <<EOF
SERVER=2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a
PORT=443
UUID=00000000-0000-4000-8000-000000000002
REALITY_PUBLIC_KEY=test-public-key
REALITY_SHORT_ID=abcdef0123456789
FLOW=xtls-rprx-vision
SNI=www.cloudflare.com
EOF
chmod 600 "$RUNTIME"
chmod 600 "$CLIENT"
make_fake_deploy "$DEPLOY" "$CALL_LOG"
make_fake_detect "$DETECT" "2a05:f480:2000:26d0:5400:6ff:fe8e:7c7a"
make_fake_sing_box "$BINARY"
cat > "$SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' active
EOF
chmod 0755 "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
ipv6_explicit_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" "$DETECT" 2>&1)

printf '%s\n' 'test-network-detection: private address rejection'
RUNTIME="$TMP/runtime-private.conf"
CLIENT="$TMP/client-private.txt"
DEPLOY="$TMP/deploy-private.sh"
SYSTEMCTL="$TMP/systemctl-private"
DETECT="$TMP/detect-private.sh"
CALL_LOG="$TMP/call-private.log"
cat > "$RUNTIME" <<EOF
VLESS_UUID=00000000-0000-4000-8000-000000000002
REALITY_PRIVATE_KEY=test-private-key
REALITY_SHORT_ID=abcdef0123456789
SOCKS_USERNAME=gateway
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token
SERVER_ADDRESS_MODE=ipv4
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
chmod 600 "$RUNTIME"
chmod 600 "$CLIENT"
make_fake_deploy "$DEPLOY" "$CALL_LOG"
make_fake_detect "$DETECT" ""
make_fake_sing_box "$BINARY"
cat > "$SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' active
EOF
chmod 0755 "$SYSTEMCTL"
BOOTSTRAP_CALL_LOG="$CALL_LOG"
if private_output=$(run_bootstrap "$RUNTIME" "$CLIENT" "$BINARY" "$DEPLOY" "$SYSTEMCTL" "$DETECT" 2>&1); then
  printf 'test-network-detection: private address was accepted\n' >&2
  exit 1
fi

printf '%s\n' 'test-network-detection: passed'