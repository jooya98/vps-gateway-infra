#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$ROOT/scripts/validate-repository.sh"
"$ROOT/tests/test-security-policy.sh"
if command -v sing-box >/dev/null 2>&1; then
  "$ROOT/tests/test-gateway-profile.sh"
else
  printf '%s\n' 'test-local: SKIP gateway config acceptance (install sing-box to enable this test)'
fi
printf '%s\n' 'test-local: passed'
