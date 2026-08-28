#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); TMP=$(mktemp -d); PID=; trap '[[ -n "${PID:-}" ]] && kill "$PID" 2>/dev/null || true; rm -rf "$TMP"' EXIT
command -v sniproxy >/dev/null || { echo 'sniproxy runtime test: binary missing' >&2; exit 1; }; command -v dig >/dev/null || { echo 'sniproxy runtime test: dig missing' >&2; exit 1; }
cat > "$TMP/runtime.env" <<'EOF'
VLESS_UUID=00000000-0000-4000-8000-000000000001
REALITY_PRIVATE_KEY=test-reality-private-key
REALITY_SHORT_ID=0000000000000001
SOCKS_USERNAME=test-user
SOCKS_PASSWORD=test-socks-password
TRANSPORT_PASSWORD=test-transport-password
SNIPROXY_PUBLIC_IPV4=127.0.0.1
DNS_ALLOWED_CIDRS='127.0.0.1/32,allow'
SING_BOX_LOG_LEVEL=warn
EOF
OUT_DIR="$TMP/rendered" PROFILE=gateway-resilient ENV_FILE="$TMP/runtime.env" "$ROOT/deploy/render.sh"
install -d -m 0755 /etc/sniproxy; install -m 0644 "$TMP/rendered/sniproxy/config.yaml" /etc/sniproxy/config.yaml; install -m 0644 "$TMP/rendered/sniproxy/domains.csv" /etc/sniproxy/domains.csv; install -m 0644 "$TMP/rendered/sniproxy/cidr.csv" /etc/sniproxy/cidr.csv
SNIPROXY_GENERAL__PREFERRED_VERSION=ipv4only sniproxy --config /etc/sniproxy/config.yaml > "$TMP/sniproxy.log" 2>&1 & PID=$!; sleep 2
if ! kill -0 "$PID" 2>/dev/null; then echo 'sniproxy failed to stay alive:'; cat "$TMP/sniproxy.log"; exit 1; fi
selected=$(dig +short @127.0.0.1 openai.com A | tail -1); [[ "$selected" == 127.0.0.1 ]] || { echo "unexpected selected DNS answer: $selected"; cat "$TMP/sniproxy.log"; exit 1; }
normal=$(dig +short @127.0.0.1 example.com A | head -1); [[ -n "$normal" && "$normal" != 127.0.0.1 ]] || { echo "unexpected normal DNS answer: $normal"; cat "$TMP/sniproxy.log"; exit 1; }
code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 12 --resolve openai.com:443:127.0.0.1 https://openai.com/ || true); [[ "$code" =~ ^[0-9]{3}$ ]] || { echo 'selected HTTPS did not produce an HTTP response:'; cat "$TMP/sniproxy.log"; exit 1; }
if dig +short @127.0.0.1 definitely-not-a-real-domain-for-gateway.invalid A | grep -q .; then echo 'unexpected DNS answer for nonexistent domain' >&2; exit 1; fi
printf 'sniproxy-runtime: selected=%s normal=%s https_status=%s\n' "$selected" "$normal" "$code"
