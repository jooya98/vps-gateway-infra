#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
PROFILE_FILE=${PROFILE_FILE:-"$ROOT/config/profiles/gateway.env.example"}
CERTBOT_BIN=${CERTBOT_BIN:-/usr/local/bin/certbot}
CREDENTIALS_PATH=${CERTBOT_CREDENTIALS_PATH:-/root/.secrets/certbot/cloudflare.ini}
CERTBOT_NAME=${TLS_CERTBOT_NAME:-echo-gateway}
CERT_DIR=${CERT_DIR:-/etc/letsencrypt/live/$CERTBOT_NAME}
CERT_PATH=${TLS_CERT_PATH:-/etc/sing-box/server.crt}
KEY_PATH=${TLS_KEY_PATH:-/etc/sing-box/server.key}

fail(){ printf 'tls: %s\n' "$1" >&2; exit 1; }
[[ $(id -u) == 0 ]] || fail 'root is required'
[[ -f "$RUNTIME_FILE" && -f "$PROFILE_FILE" ]] || fail 'runtime/profile file missing'

set -a
source "$RUNTIME_FILE"
source "$PROFILE_FILE"
set +a

[[ "${ENABLE_DIRECT_TLS:-0}" == 1 ]] || { printf '%s\n' 'tls: direct TLS disabled; certificate step skipped'; exit 0; }
[[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] || fail 'CLOUDFLARE_API_TOKEN is required'
[[ -n "${PUBLIC_HOSTNAME:-}" && -n "${DIRECT_HOSTNAME:-}" ]] || fail 'public/direct hostnames are required'

install -d -m 0700 "$(dirname "$CREDENTIALS_PATH")"
umask 077
cat > "$CREDENTIALS_PATH" <<EOF
# Restricted Cloudflare API token for Certbot DNS-01.
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF
chmod 0600 "$CREDENTIALS_PATH"

if [[ ! -x "$CERTBOT_BIN" ]]; then
  command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
  command -v python3 -m venv >/dev/null 2>&1 || true
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv
  install -d -m 0755 /opt/certbot
  python3 -m venv /opt/certbot
  /opt/certbot/bin/pip install --upgrade pip >/dev/null
  /opt/certbot/bin/pip install --upgrade certbot certbot-dns-cloudflare >/dev/null
  ln -sfn /opt/certbot/bin/certbot "$CERTBOT_BIN"
fi

"$CERTBOT_BIN" plugins 2>/dev/null | grep -q 'dns-cloudflare' || {
  /opt/certbot/bin/pip install --upgrade certbot-dns-cloudflare >/dev/null 2>&1 || fail 'certbot-dns-cloudflare plugin is unavailable'
}

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

install -m 0644 "$CERT_DIR/fullchain.pem" "$CERT_PATH"
install -m 0600 "$CERT_DIR/privkey.pem" "$KEY_PATH"

HOOK_DIR=/etc/letsencrypt/renewal-hooks/deploy
HOOK="$HOOK_DIR/joohar-sing-box.sh"
install -d -m 0755 "$HOOK_DIR"
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CERTBOT_LINEAGE=${RENEWED_LINEAGE:-}
[[ -n "$CERTBOT_LINEAGE" ]] || exit 0
install -m 0644 "$CERTBOT_LINEAGE/fullchain.pem" /etc/sing-box/server.crt
install -m 0600 "$CERTBOT_LINEAGE/privkey.pem" /etc/sing-box/server.key
systemctl try-restart sing-box.service >/dev/null 2>&1 || true
EOF
chmod 0755 "$HOOK"

printf 'tls: certificate ready for %s and %s\n' "$PUBLIC_HOSTNAME" "$DIRECT_HOSTNAME"
