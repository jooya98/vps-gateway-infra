#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail=0
while IFS= read -r f; do
  if ! bash -n "$f"; then fail=1; fi
done < <(find "$ROOT/bootstrap" "$ROOT/deploy" "$ROOT/scripts" "$ROOT/tests" -type f -name '*.sh' -print)

if grep -RInE 'VLESS_UUID=[^[:space:]]+|REALITY_PRIVATE_KEY=[^[:space:]]+|SOCKS_PASSWORD=[^[:space:]]+|CLOUDFLARED_TUNNEL_TOKEN=[^[:space:]]+' "$ROOT" --exclude-dir=.git --exclude-dir=reference --exclude='*.sh' >/dev/null; then
  printf 'secret-check: possible secret assignment found\n' >&2
  fail=1
fi

if grep -RInE 'PRIVATE_KEY|SOCKS_PASSWORD|VLESS_UUID|TUNNEL_TOKEN' "$ROOT/.generated" 2>/dev/null | grep -v '\${' >/dev/null; then
  printf 'secret-check: secret variable name leaked into generated output\n' >&2
  fail=1
fi

exit "$fail"
