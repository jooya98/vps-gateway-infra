#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
PROFILE_FILE=${PROFILE_FILE:-"$ROOT/config/profiles/gateway.env.example"}
CERTBOT_BIN=${CERTBOT_BIN:-/usr/bin/certbot}
CREDENTIALS_PATH=${CERTBOT_CREDENTIALS_PATH:-/root/.secrets/certbot/cloudflare.ini}
CERTBOT_NAME=${TLS_CERTBOT_NAME:-echo-gateway}
CERT_DIR=${CERT_DIR:-/etc/letsencrypt/live/$CERTBOT_NAME}
CERT_PATH=${TLS_CERT_PATH:-/etc/sing-box/server.crt}
KEY_PATH=${TLS_KEY_PATH:-/etc/sing-box/server.key}

fail(){ printf 'tls: %s\n' "$1" >&2; exit 1; }
[[ $(id -u) == 0 ]] || fail 'root is required'
[[ -f "$RUNTIME_FILE" && -f "$PROFILE_FILE" ]] || fail 'runtime/profile file missing'

set -a
source "$ROOT/config/defaults.env.example"
source "$PROFILE_FILE"
source "$RUNTIME_FILE"
set +a

[[ "${ENABLE_DIRECT_TLS:-0}" == 1 ]] || { printf '%s\n' 'tls: direct TLS disabled; certificate step skipped'; exit 0; }
[[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] || fail 'Cloudflare API token is required'
[[ -n "${PUBLIC_HOSTNAME:-}" && -n "${DIRECT_HOSTNAME:-}" ]] || fail 'public/direct hostnames are required'

if [[ ! -x "$CERTBOT_BIN" ]]; then
  command -v apt-get >/dev/null 2>&1 || fail 'apt-get is required to install Certbot'
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-dns-cloudflare
fi

"$CERTBOT_BIN" plugins 2>/dev/null | grep -q 'dns-cloudflare' || fail 'Certbot DNS Cloudflare plugin is unavailable'

install -d -m 0700 "$(dirname "$CREDENTIALS_PATH")"
umask 077
cat > "$CREDENTIALS_PATH" <<EOF
# Root-only Cloudflare token for Certbot DNS-01.
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF
chmod 0600 "$CREDENTIALS_PATH"

EMAIL_ARGS=(--register-unsafely-without-email)
if [[ -n "${CERTBOT_EMAIL:-}" ]]; then EMAIL_ARGS=(--email "$CERTBOT_EMAIL"); fi

"$CERTBOT_BIN" certonly \
  --non-interactive \
  --agree-tos \
  "${EMAIL_ARGS[@]}" \
  --dns-cloudflare \
  --dns-cloudflare-credentials "$CREDENTIALS_PATH" \
  --dns-cloudflare-propagation-seconds 30 \
  --cert-name "$CERTBOT_NAME" \
  --keep-until-expiring \
  -d "$PUBLIC_HOSTNAME" \
  -d "$DIRECT_HOSTNAME"

[[ -s "$CERT_DIR/fullchain.pem" && -s "$CERT_DIR/privkey.pem" ]] || fail 'certificate files were not created'
install -d -m 0755 "$(dirname "$CERT_PATH")" "$(dirname "$KEY_PATH")"
install -m 0644 "$CERT_DIR/fullchain.pem" "$CERT_PATH"
install -m 0600 "$CERT_DIR/privkey.pem" "$KEY_PATH"

HOOK_DIR=/etc/letsencrypt/renewal-hooks/deploy
HOOK="$HOOK_DIR/joohar-sing-box.sh"
install -d -m 0755 "$HOOK_DIR"
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
lineage=${RENEWED_LINEAGE:-}
[[ -n "$lineage" ]] || exit 0
install -d -m 0755 /etc/sing-box
install -m 0644 "$lineage/fullchain.pem" /etc/sing-box/server.crt
install -m 0600 "$lineage/privkey.pem" /etc/sing-box/server.key
systemctl try-restart sing-box.service >/dev/null 2>&1 || true
EOF
chmod 0755 "$HOOK"

printf 'tls: certificate ready for %s and %s\n' "$PUBLIC_HOSTNAME" "$DIRECT_HOSTNAME"
