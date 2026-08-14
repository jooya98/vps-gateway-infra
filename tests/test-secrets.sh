#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
RUNTIME="$TMP/runtime.conf"
CLIENT="$TMP/client-info.txt"
FAKE_BIN="$TMP/sing-box"
cat > "$FAKE_BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'PrivateKey: test-private-key-material' 'PublicKey: test-public-key-material'
EOF
chmod 0755 "$FAKE_BIN"

printf '%s\n' 'test-secrets: generate with fake sing-box'
generator_output=$(RUNTIME_FILE="$RUNTIME" CLIENT_INFO_FILE="$CLIENT" SING_BOX_BIN="$FAKE_BIN" "$ROOT/scripts/generate-secrets.sh")
! grep -q 'test-private-key-material\|test-public-key-material' <<<"$generator_output"
[[ "$(stat -c '%a' "$RUNTIME")" == 600 ]]
[[ "$(stat -c '%a' "$CLIENT")" == 600 ]]
if [[ "$(id -u)" == 0 ]]; then
  [[ "$(stat -c '%u' "$RUNTIME")" == 0 ]]
  [[ "$(stat -c '%u' "$CLIENT")" == 0 ]]
fi
grep -q '^CLOUDFLARED_TUNNEL_TOKEN=$' "$RUNTIME"
! grep -q 'REALITY_PRIVATE_KEY' "$CLIENT"
! grep -q 'test-private-key-material' "$CLIENT"

printf '%s\n' 'test-secrets: incomplete runtime rejected'
if RUNTIME_FILE="$RUNTIME" CLIENT_INFO_FILE="$CLIENT" "$ROOT/scripts/validate-secrets.sh" >/dev/null 2>&1; then
  printf 'test-secrets: incomplete runtime was accepted\n' >&2
  exit 1
fi

python3 - "$RUNTIME" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
text = p.read_text().replace('CLOUDFLARED_TUNNEL_TOKEN=\n', 'CLOUDFLARED_TUNNEL_TOKEN=test-cloudflare-token\n')
p.write_text(text)
PY
chmod 0600 "$RUNTIME"
RUNTIME_FILE="$RUNTIME" CLIENT_INFO_FILE="$CLIENT" "$ROOT/scripts/validate-secrets.sh" >/dev/null

printf '%s\\n' 'test-secrets: malformed runtime rejected'
cp "$RUNTIME" "$TMP/malformed.conf"
python3 - "$TMP/malformed.conf" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
text = p.read_text().replace('VLESS_UUID=', 'VLESS_UUID=not-a-uuid\n# removed:')
p.write_text(text)
PY
chmod 0600 "$TMP/malformed.conf"
if RUNTIME_FILE="$TMP/malformed.conf" CLIENT_INFO_FILE="$CLIENT" "$ROOT/scripts/validate-secrets.sh" >/dev/null 2>&1; then
  printf 'test-secrets: malformed UUID was accepted\n' >&2
  exit 1
fi

printf '%s\\n' 'test-secrets: UUIDv7 is accepted'
cp "$RUNTIME" "$TMP/uuidv7.conf"
python3 - "$TMP/uuidv7.conf" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
text = p.read_text().replace('VLESS_UUID=', 'VLESS_UUID=0192f0c8-1e5b-7cc3-98c4-dc0c0c072942\n# replaced:')
p.write_text(text)
PY
chmod 0600 "$TMP/uuidv7.conf"
if ! RUNTIME_FILE="$TMP/uuidv7.conf" CLIENT_INFO_FILE="$CLIENT" "$ROOT/scripts/validate-secrets.sh" >/dev/null 2>&1; then
  printf 'test-secrets: UUIDv7 was rejected\n' >&2
  exit 1
fi

printf '%s\\n' 'test-secrets: overwrite protection'
if RUNTIME_FILE="$RUNTIME" CLIENT_INFO_FILE="$TMP/new-client.txt" SING_BOX_BIN="$FAKE_BIN" "$ROOT/scripts/generate-secrets.sh" >/dev/null 2>&1; then
  printf 'test-secrets: existing runtime was overwritten\n' >&2
  exit 1
fi
printf '%s\n' 'test-secrets: passed'
