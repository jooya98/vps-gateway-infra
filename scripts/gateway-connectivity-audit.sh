#!/usr/bin/env bash
set -euo pipefail

# Connectivity audit: DNS -> TCP -> TLS -> HTTP, with optional SOCKS5 proxy.
INVENTORY=${1:-config/gateway/domains/ai-domains.txt}
PROXY=${PROXY:-}
TIMEOUT=${TIMEOUT:-8}
command -v curl >/dev/null || { echo 'audit: curl is required' >&2; exit 1; }
command -v openssl >/dev/null || { echo 'audit: openssl is required' >&2; exit 1; }
command -v getent >/dev/null || { echo 'audit: getent is required' >&2; exit 1; }

printf '%-40s %-9s %-9s %-9s %-18s %s\n' DOMAIN DNS TCP TLS HTTP PATH
printf '%-40s %-9s %-9s %-9s %-18s %s\n' '----------------------------------------' '---------' '---------' '---------' '------------------' '----'
while IFS= read -r domain; do
  domain=${domain%%#*}; domain=${domain//[$'\r\t ']/}
  [[ -z "$domain" ]] && continue
  ip=$(getent ahostsv4 "$domain" | awk 'NR==1{print $1}') || true
  if [[ -z "$ip" ]]; then printf '%-40s %-9s %-9s %-9s %-18s %s\n' "$domain" FAIL - - DNS_FAIL DIRECT; continue; fi
  tcp=FAIL; tls=FAIL; http=FAIL
  if timeout "$TIMEOUT" bash -c "</dev/tcp/$ip/443" 2>/dev/null; then tcp=PASS; else printf '%-40s %-9s %-9s %-9s %-18s %s\n' "$domain" PASS FAIL - TCP_FAIL DIRECT; continue; fi
  if timeout "$TIMEOUT" openssl s_client -connect "$ip:443" -servername "$domain" -brief </dev/null >/dev/null 2>&1; then tls=PASS; else printf '%-40s %-9s %-9s %-9s %-18s %s\n' "$domain" PASS PASS FAIL TLS_FAIL "${PROXY:+PROXY} ${PROXY:-DIRECT}"; continue; fi
  args=(--silent --show-error --output /dev/null --write-out '%{http_code}' --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" --resolve "$domain:443:$ip" "https://$domain/")
  [[ -n "$PROXY" ]] && args=(--proxy "$PROXY" "${args[@]}")
  code=$(curl "${args[@]}" 2>/dev/null || true)
  if [[ "$code" =~ ^[0-9]{3}$ ]]; then http="$code"; else http=HTTP_FAIL; fi
  printf '%-40s %-9s %-9s %-9s %-18s %s\n' "$domain" PASS "$tcp" "$tls" "$http" "${PROXY:+PROXY} ${PROXY:-DIRECT}"
done < "$INVENTORY"
