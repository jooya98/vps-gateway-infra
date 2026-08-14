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
EOF

printf '%s\n' 'test: render and validate with temporary values'
ENV_FILE="$TMP_ENV" OUT_DIR="$TMP_OUT" "$ROOT/deploy/render.sh"
OUT_DIR="$TMP_OUT" "$ROOT/deploy/validate.sh"
DRY_RUN=1 POLICY_FILE="$ROOT/config/firewall/policy.env.example" "$ROOT/scripts/apply-firewall.sh" >/dev/null

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
