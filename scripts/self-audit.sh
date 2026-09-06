#!/usr/bin/env bash
set -euo pipefail

# Read-only post-deployment validation for the comprehensive gateway profile.
# This script must never mutate gateway state.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
PROFILE=${PROFILE:-gateway}
PROFILE_FILE="$ROOT/config/profiles/$PROFILE.env.example"
SSH_CONFIG=/etc/ssh/sshd_config
SSH_DROPIN_DIR=/etc/ssh/sshd_config.d
SING_BOX_CONFIG=${SING_BOX_CONFIG_PATH:-/etc/sing-box/config.json}
SING_BOX_BIN=${SING_BOX_BIN:-/usr/local/bin/sing-box}
CLOUDFLARED_BIN=${CLOUDFLARED_BIN:-/usr/local/bin/cloudflared}
CLOUDFLARED_CONFIG=${CLOUDFLARED_CONFIG_PATH:-/etc/cloudflared/echo-config.yml}
CLOUDFLARED_CREDENTIALS=${CLOUDFLARED_CREDENTIALS_PATH:-/etc/cloudflared/echo-tunnel.json}
TLS_CERT=${TLS_CERT_PATH:-/etc/sing-box/server.crt}
TLS_KEY=${TLS_KEY_PATH:-/etc/sing-box/server.key}
CLOUDFLARE_STATE=/root/vps-gateway-cloudflared.conf
MULTI_RUNTIME_FILE=/root/vps-gateway-multiprotocol.conf

PASS=0
FAIL=0
WARN=0

ok(){ printf '[PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad(){ printf '[FAIL] %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
warn(){ printf '[WARN] %s\n' "$1" >&2; WARN=$((WARN+1)); }
check(){ local label=$1; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi; }

mode_is(){ local expected=$1 file=$2 actual; actual=$(stat -c '%a' "$file" 2>/dev/null || printf ''); [[ "$actual" == "$expected" ]]; }
owned_by(){ local owner=$1 group=$2 file=$3 actual; actual=$(stat -c '%U:%G' "$file" 2>/dev/null || printf ''); [[ "$actual" == "$owner:$group" ]]; }

[[ $(id -u) == 0 ]] || { printf 'self-audit: root is required\n' >&2; exit 1; }
[[ -f "$RUNTIME_FILE" ]] || { printf 'self-audit: runtime file missing: %s\n' "$RUNTIME_FILE" >&2; exit 1; }
[[ -f "$PROFILE_FILE" ]] || { printf 'self-audit: profile missing: %s\n' "$PROFILE_FILE" >&2; exit 1; }
set -a
source "$ROOT/config/defaults.env.example"
source "$PROFILE_FILE"
source "$RUNTIME_FILE"
[[ -f "$MULTI_RUNTIME_FILE" ]] && source "$MULTI_RUNTIME_FILE"
set +a

printf '%s\n' '=== vps-gateway self-audit ==='
printf 'profile=%s\n' "$PROFILE"
printf 'runtime=%s\n' "$RUNTIME_FILE"
printf '%s\n' 'Read-only checks only; no gateway state is modified.'

# Runtime secrets/state permissions.
check "runtime file is root-owned and mode 0600" test -f "$RUNTIME_FILE"
mode_is 600 "$RUNTIME_FILE" && ok 'runtime file mode is 0600' || bad 'runtime file mode is not 0600'
owned_by root root "$RUNTIME_FILE" && ok 'runtime file owner is root:root' || bad 'runtime file owner is not root:root'
if [[ -f "$MULTI_RUNTIME_FILE" ]]; then
  mode_is 600 "$MULTI_RUNTIME_FILE" && ok 'multiprotocol runtime mode is 0600' || bad 'multiprotocol runtime mode is not 0600'
  owned_by root root "$MULTI_RUNTIME_FILE" && ok 'multiprotocol runtime owner is root:root' || bad 'multiprotocol runtime owner is not root:root'
else
  bad 'multiprotocol runtime file is missing'
fi

# Administrative user and SSH key permissions.
[[ -n "${ADMIN_USER:-}" ]] && ok 'ADMIN_USER is configured' || bad 'ADMIN_USER is missing from runtime'
if [[ -n "${ADMIN_USER:-}" ]] && id "$ADMIN_USER" >/dev/null 2>&1; then
  ok "admin user exists: $ADMIN_USER"
  ADMIN_UID=$(id -u "$ADMIN_USER")
  HOME_DIR=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
  [[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] && ok 'admin home directory exists' || bad 'admin home directory is missing'
  [[ "$ADMIN_UID" != 0 ]] && ok 'admin user is non-root' || bad 'admin user unexpectedly has UID 0'
  id -nG "$ADMIN_USER" | tr ' ' '\n' | grep -Fxq sudo && ok 'admin user belongs to sudo group' || bad 'admin user is not in sudo group'
  SSH_DIR="$HOME_DIR/.ssh"
  AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
  [[ -d "$SSH_DIR" ]] && ok 'admin .ssh directory exists' || bad 'admin .ssh directory is missing'
  if [[ -d "$SSH_DIR" ]]; then
    mode_is 700 "$SSH_DIR" && ok 'admin .ssh mode is 0700' || bad 'admin .ssh mode is not 0700'
    owned_by "$ADMIN_USER" "$ADMIN_USER" "$SSH_DIR" && ok 'admin .ssh owner is correct' || bad 'admin .ssh owner is incorrect'
  fi
  [[ -s "$AUTHORIZED_KEYS" ]] && ok 'authorized_keys exists and is non-empty' || bad 'authorized_keys is missing or empty'
  if [[ -e "$AUTHORIZED_KEYS" ]]; then
    mode_is 600 "$AUTHORIZED_KEYS" && ok 'authorized_keys mode is 0600' || bad 'authorized_keys mode is not 0600'
    owned_by "$ADMIN_USER" "$ADMIN_USER" "$AUTHORIZED_KEYS" && ok 'authorized_keys owner is correct' || bad 'authorized_keys owner is incorrect'
    ssh-keygen -lf "$AUTHORIZED_KEYS" >/dev/null 2>&1 && ok 'authorized_keys contains parseable SSH public key material' || bad 'authorized_keys is not parseable by ssh-keygen'
  fi
  SUDOERS_FILE="/etc/sudoers.d/$ADMIN_USER"
  [[ -f "$SUDOERS_FILE" ]] && ok 'admin sudoers file exists' || bad 'admin sudoers file is missing'
  if [[ -f "$SUDOERS_FILE" ]]; then
    mode_is 440 "$SUDOERS_FILE" && ok 'admin sudoers mode is 0440' || bad 'admin sudoers mode is not 0440'
    owned_by root root "$SUDOERS_FILE" && ok 'admin sudoers owner is root:root' || bad 'admin sudoers owner is incorrect'
  fi
else
  bad 'admin user lookup failed'
fi

# Effective OpenSSH policy. sshd -T is authoritative for parsed configuration.
if command -v sshd >/dev/null 2>&1; then
  SSHD_EFFECTIVE=$(sshd -T 2>/dev/null || true)
  [[ -n "$SSHD_EFFECTIVE" ]] && ok 'effective sshd configuration parses' || bad 'effective sshd configuration failed to parse'
  [[ "$SSHD_EFFECTIVE" == *$'port 22\n'* ]] && ok 'sshd effective port is 22' || bad 'sshd effective port is not 22'
  [[ "$SSHD_EFFECTIVE" == *$'pubkeyauthentication yes\n'* ]] && ok 'sshd public-key authentication is enabled' || bad 'sshd public-key authentication is not enabled'
  [[ "$SSHD_EFFECTIVE" == *$'passwordauthentication no\n'* ]] && ok 'sshd password authentication is disabled' || bad 'sshd password authentication is not disabled'
  [[ "$SSHD_EFFECTIVE" == *$'kbdinteractiveauthentication no\n'* ]] && ok 'sshd keyboard-interactive authentication is disabled' || bad 'sshd keyboard-interactive authentication is not disabled'
  [[ "$SSHD_EFFECTIVE" == *$'permitrootlogin no\n'* ]] && ok 'sshd root login is disabled' || bad 'sshd root login is not disabled'
  [[ "$SSHD_EFFECTIVE" == *$'authorizedkeysfile .ssh/authorized_keys\n'* ]] && ok 'sshd AuthorizedKeysFile is canonical' || bad 'sshd AuthorizedKeysFile is not canonical'
else
  bad 'sshd binary is missing'
fi
[[ -f "$SSH_CONFIG" ]] && ok 'managed main sshd_config exists' || bad 'managed main sshd_config is missing'
if [[ -d "$SSH_DROPIN_DIR" ]]; then
  mapfile -t PROVIDER_FRAGMENTS < <(find "$SSH_DROPIN_DIR" -maxdepth 1 -type f -name '*.conf' -print)
  if ((${#PROVIDER_FRAGMENTS[@]} == 0)); then
    ok 'no active SSH provider fragments remain'
  else
    bad "active SSH provider fragments remain: ${PROVIDER_FRAGMENTS[*]}"
  fi
fi

# Firewall policy and expected ingress.
if command -v ufw >/dev/null 2>&1; then
  UFW_STATUS=$(ufw status verbose 2>/dev/null || true)
  grep -q '^Status: active' <<< "$UFW_STATUS" && ok 'UFW is active' || bad 'UFW is not active'
  grep -q 'Default: deny (incoming)' <<< "$UFW_STATUS" && ok 'UFW default incoming policy is deny' || bad 'UFW default incoming policy is not deny'
  grep -q 'Default: allow (outgoing)' <<< "$UFW_STATUS" && ok 'UFW default outgoing policy is allow' || bad 'UFW default outgoing policy is not allow'
  rule_tcp(){ grep -Eq "^[^|]*${1}/tcp[[:space:]]+ALLOW" <<< "$UFW_STATUS"; }
  rule_udp(){ grep -Eq "^[^|]*${1}/udp[[:space:]]+ALLOW" <<< "$UFW_STATUS"; }
  expect_tcp(){ local p=$1; rule_tcp "$p" && ok "UFW allows TCP $p" || bad "UFW missing TCP $p"; }
  expect_udp(){ local p=$1; rule_udp "$p" && ok "UFW allows UDP $p" || bad "UFW missing UDP $p"; }
  expect_tcp 22
  [[ "$ENABLE_VLESS" == true ]] && expect_tcp "$VLESS_PORT"
  [[ "$ENABLE_SHADOWSOCKS" == true ]] && expect_tcp "$SHADOWSOCKS_PORT"
  [[ "$ENABLE_SHADOWSOCKS" == true ]] && expect_tcp "$SHADOWSOCKS_2022_PORT"
  [[ "$ENABLE_HYSTERIA2" == true ]] && expect_udp "$HYSTERIA2_PORT"
  [[ "$ENABLE_TUIC" == true ]] && expect_udp "$TUIC_PORT"
  [[ "$ENABLE_TROJAN" == true ]] && expect_tcp "$TROJAN_PORT"
  [[ "$ENABLE_DIRECT_TLS" == 1 ]] && expect_tcp "$ANYTLS_PORT"
  [[ "$ENABLE_DIRECT_TLS" == 1 ]] && expect_tcp "$VLESS_GRPC_PORT"
  [[ "$ENABLE_SOCKS" == true && "${ALLOW_PUBLIC_SOCKS:-false}" == true ]] && expect_tcp "$SOCKS_LISTEN_PORT"
  [[ "$ENABLE_SOCKS" == true && "${ALLOW_PUBLIC_SOCKS:-false}" == true ]] && expect_tcp "$HTTP_PORT"
else
  bad 'ufw binary is missing'
fi

# Listening sockets: verify public endpoints and loopback-only tunnel origins.
if command -v ss >/dev/null 2>&1; then
  TCP_LISTEN=$(ss -lntH 2>/dev/null || true)
  UDP_LISTEN=$(ss -lnuH 2>/dev/null || true)
  socket_tcp_any(){ grep -Eq "[[:space:]](0\.0\.0\.0|\*):${1}[[:space:]]" <<< "$TCP_LISTEN"; }
  socket_udp_any(){ grep -Eq "[[:space:]](0\.0\.0\.0|\*):${1}[[:space:]]" <<< "$UDP_LISTEN"; }
  socket_tcp_loopback(){ grep -Eq "[[:space:]]127\.0\.0\.1:${1}[[:space:]]" <<< "$TCP_LISTEN"; }
  expect_socket_tcp(){ local p=$1; socket_tcp_any "$p" && ok "TCP listener present on 0.0.0.0:$p" || bad "TCP listener missing on 0.0.0.0:$p"; }
  expect_socket_udp(){ local p=$1; socket_udp_any "$p" && ok "UDP listener present on 0.0.0.0:$p" || bad "UDP listener missing on 0.0.0.0:$p"; }
  expect_socket_loop(){ local p=$1; socket_tcp_loopback "$p" && ok "loopback TCP listener present on 127.0.0.1:$p" || bad "loopback TCP listener missing on 127.0.0.1:$p"; }
  expect_socket_tcp 22
  [[ "$ENABLE_VLESS" == true ]] && expect_socket_tcp "$VLESS_PORT"
  [[ "$ENABLE_SHADOWSOCKS" == true ]] && expect_socket_tcp "$SHADOWSOCKS_PORT"
  [[ "$ENABLE_SHADOWSOCKS" == true ]] && expect_socket_tcp "$SHADOWSOCKS_2022_PORT"
  [[ "$ENABLE_TROJAN" == true ]] && expect_socket_tcp "$TROJAN_PORT"
  [[ "$ENABLE_DIRECT_TLS" == 1 ]] && expect_socket_tcp "$ANYTLS_PORT"
  [[ "$ENABLE_DIRECT_TLS" == 1 ]] && expect_socket_tcp "$VLESS_GRPC_PORT"
  [[ "$ENABLE_HYSTERIA2" == true ]] && expect_socket_udp "$HYSTERIA2_PORT"
  [[ "$ENABLE_TUIC" == true ]] && expect_socket_udp "$TUIC_PORT"
  [[ "$ENABLE_SOCKS" == true && "${ALLOW_PUBLIC_SOCKS:-false}" == true ]] && expect_socket_tcp "$SOCKS_LISTEN_PORT"
  [[ "$ENABLE_SOCKS" == true && "${ALLOW_PUBLIC_SOCKS:-false}" == true ]] && expect_socket_tcp "$HTTP_PORT"
  expect_socket_loop "$VLESS_WS_PORT"
  expect_socket_loop "$VMESS_WS_PORT"
  expect_socket_loop "$VLESS_HTTPUPGRADE_PORT"
else
  bad 'ss command is missing'
fi

# Services and generated configuration.
if systemctl --quiet is-enabled sing-box.service 2>/dev/null && systemctl --quiet is-active sing-box.service 2>/dev/null; then
  ok 'sing-box.service is enabled and active'
else
  bad 'sing-box.service is not both enabled and active'
fi
if systemctl --quiet is-enabled cloudflared-echo.service 2>/dev/null && systemctl --quiet is-active cloudflared-echo.service 2>/dev/null; then
  ok 'cloudflared-echo.service is enabled and active'
else
  bad 'cloudflared-echo.service is not both enabled and active'
fi
[[ -x "$SING_BOX_BIN" ]] && ok 'sing-box binary exists and is executable' || bad 'sing-box binary is missing or not executable'
[[ -x "$CLOUDFLARED_BIN" ]] && ok 'cloudflared binary exists and is executable' || bad 'cloudflared binary is missing or not executable'
[[ -f "$SING_BOX_CONFIG" ]] && ok 'sing-box config exists' || bad 'sing-box config is missing'
if [[ -f "$SING_BOX_CONFIG" && -x "$SING_BOX_BIN" ]]; then
  "$SING_BOX_BIN" check -c "$SING_BOX_CONFIG" >/dev/null 2>&1 && ok 'sing-box config passes native validation' || bad 'sing-box config fails native validation'
fi
[[ -f "$SING_BOX_CONFIG" ]] && mode_is 600 "$SING_BOX_CONFIG" && ok 'sing-box config mode is 0600' || [[ ! -f "$SING_BOX_CONFIG" ]] || bad 'sing-box config mode is not 0600'
[[ -f "$CLOUDFLARED_CONFIG" ]] && ok 'cloudflared config exists' || bad 'cloudflared config is missing'
[[ -f "$CLOUDFLARED_CREDENTIALS" ]] && ok 'cloudflared tunnel credentials exist' || bad 'cloudflared tunnel credentials are missing'
if [[ -f "$CLOUDFLARED_CREDENTIALS" ]]; then
  mode_is 600 "$CLOUDFLARED_CREDENTIALS" && ok 'cloudflared credentials mode is 0600' || bad 'cloudflared credentials mode is not 0600'
  owned_by root root "$CLOUDFLARED_CREDENTIALS" && ok 'cloudflared credentials owner is root:root' || bad 'cloudflared credentials owner is incorrect'
fi
if [[ -f "$CLOUDFLARED_CONFIG" && -x "$CLOUDFLARED_BIN" ]]; then
  "$CLOUDFLARED_BIN" --config "$CLOUDFLARED_CONFIG" tunnel ingress validate >/dev/null 2>&1 && ok 'cloudflared ingress config passes validation' || bad 'cloudflared ingress config fails validation'
fi
[[ -f "$CLOUDFLARE_STATE" ]] && mode_is 600 "$CLOUDFLARE_STATE" && ok 'cloudflared state mode is 0600' || [[ ! -f "$CLOUDFLARE_STATE" ]] || bad 'cloudflared state mode is not 0600'

# TLS material and renewal hook.
[[ -s "$TLS_CERT" ]] && ok 'TLS certificate exists' || bad 'TLS certificate is missing or empty'
[[ -s "$TLS_KEY" ]] && ok 'TLS private key exists' || bad 'TLS private key is missing or empty'
if [[ -f "$TLS_KEY" ]]; then
  mode_is 600 "$TLS_KEY" && ok 'TLS private key mode is 0600' || bad 'TLS private key mode is not 0600'
  owned_by root root "$TLS_KEY" && ok 'TLS private key owner is root:root' || bad 'TLS private key owner is incorrect'
fi
[[ -x /etc/letsencrypt/renewal-hooks/deploy/joohar-sing-box.sh ]] && ok 'TLS renewal hook is installed' || bad 'TLS renewal hook is missing or not executable'

# Local DNS sanity: both configured hostnames must resolve from the VPS.
if command -v getent >/dev/null 2>&1; then
  getent ahostsv4 "$PUBLIC_HOSTNAME" >/dev/null 2>&1 && ok "public hostname resolves: $PUBLIC_HOSTNAME" || bad "public hostname does not resolve: $PUBLIC_HOSTNAME"
  getent ahostsv4 "$DIRECT_HOSTNAME" >/dev/null 2>&1 && ok "direct hostname resolves: $DIRECT_HOSTNAME" || bad "direct hostname does not resolve: $DIRECT_HOSTNAME"
else
  warn 'getent is unavailable; hostname resolution checks skipped'
fi

# Security advisory intentionally does not fail deployment: current service unit runs sing-box as root.
if systemctl cat sing-box.service 2>/dev/null | grep -Eq '^User='; then
  ok 'sing-box systemd unit declares an explicit service user'
else
  warn 'sing-box systemd unit runs as root (no User= directive); consider a future least-privilege hardening pass'
fi

printf '%s\n' '=== self-audit summary ==='
printf 'PASS=%d FAIL=%d WARN=%d\n' "$PASS" "$FAIL" "$WARN"
if ((FAIL)); then
  printf '%s\n' 'self-audit: FAILED' >&2
  exit 1
fi
printf '%s\n' 'self-audit: PASSED'
