#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

printf '%s\n' 'test: shell syntax'
"$ROOT/scripts/validate-repository.sh"

TMP_ENV=$(mktemp)
TMP_OUT=$(mktemp -d)
trap 'rm -f "$TMP_ENV"; rm -rf "$TMP_OUT"' EXIT
cat > "$TMP_ENV" <<'EOF'
VLESS_UUID=00000000-0000-4000-8000-000000000001
REALITY_PRIVATE_KEY=test-reality-private-key
REALITY_SHORT_ID=0000000000000001
SOCKS_USERNAME=test-user
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflared-token
SING_BOX_VERSION=1.13.18
CLOUDFLARED_VERSION=2026.8.1
EOF

printf '%s\n' 'test: installer architecture and version override'
sing_output=$(SING_BOX_VERSION=9.9.9 DRY_RUN=1 "$ROOT/scripts/install-sing-box.sh")
cloud_output=$(CLOUDFLARED_VERSION=2099.1 DRY_RUN=1 "$ROOT/scripts/install-cloudflared.sh")
grep -q 'version=9.9.9' <<<"$sing_output"
grep -q 'version=2099.1' <<<"$cloud_output"
grep -Eq 'architecture=(amd64|arm64)' <<<"$sing_output"
grep -Eq 'architecture=(amd64|arm64)' <<<"$cloud_output"

printf '%s\n' 'test: render and validate with temporary values'
ENV_FILE="$TMP_ENV" OUT_DIR="$TMP_OUT" "$ROOT/deploy/render.sh"
OUT_DIR="$TMP_OUT" "$ROOT/deploy/validate.sh"
DRY_RUN=1 POLICY_FILE="$ROOT/config/firewall/policy.env.example" "$ROOT/scripts/apply-firewall.sh" >/dev/null

printf '%s\n' 'test: dry-run deployment order and redaction'
deploy_output=$(OUT_DIR="$TMP_OUT/deploy" "$ROOT/deploy/deploy.sh" --dry-run --env-file "$TMP_ENV")
! grep -q 'test-reality-private-key\|test-socks-password\|test-cloudflared-token' <<<"$deploy_output"
grep -q 'deploy: install official sing-box' <<<"$deploy_output"
grep -q 'deploy: install official cloudflared' <<<"$deploy_output"
grep -q 'deploy: validate generated configuration' <<<"$deploy_output"
grep -q 'deploy: install systemd units' <<<"$deploy_output"

printf '%s\n' 'test: missing secret rejection'
if env -i PATH="$PATH" ROOT="$ROOT" OUT_DIR="$TMP_OUT/missing" "$ROOT/deploy/render.sh" >/dev/null 2>&1; then
  printf 'test: missing variables were accepted\n' >&2
  exit 1
fi

if git -C "$ROOT" ls-files --cached --others --exclude-standard -z | tr '\0' '\n' | grep -v '^tests/' | tr '\n' '\0' | xargs -0 grep -IlE 'test-reality-private-key|test-socks-password|test-cloudflared-token' >/dev/null 2>&1; then
  printf 'test: temporary secret leaked into tracked or non-ignored source\n' >&2
  exit 1
fi
printf '%s\n' 'test: passed'
