#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
PROFILE_FILE=${PROFILE_FILE:-"$ROOT/config/profiles/gateway.env.example"}
STATE_FILE=${STATE_FILE:-/root/vps-gateway-cloudflared.conf}
CONFIG_PATH=${CLOUDFLARED_CONFIG_PATH:-/etc/cloudflared/echo-config.yml}
CREDENTIALS_PATH=${CLOUDFLARED_CREDENTIALS_PATH:-/etc/cloudflared/echo-tunnel.json}
SERVICE_PATH=${SERVICE_PATH:-/etc/systemd/system/cloudflared-echo.service}
TEMPLATE="$ROOT/templates/cloudflared/multiprotocol-config.yml.tmpl"
SERVICE_TEMPLATE="$ROOT/templates/cloudflared/multiprotocol.service.tmpl"
CF_API=${CF_API:-https://api.cloudflare.com/client/v4}
DRY_RUN=${DRY_RUN:-0}

fail(){ printf 'cloudflare: %s\n' "$1" >&2; exit 1; }
[[ $(id -u) == 0 ]] || fail 'root is required'
[[ -f "$RUNTIME_FILE" && -f "$PROFILE_FILE" ]] || fail 'runtime/profile file missing'
command -v curl >/dev/null 2>&1 || fail 'curl is required'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
command -v openssl >/dev/null 2>&1 || fail 'openssl is required'

set -a
source "$ROOT/config/defaults.env.example"
source "$PROFILE_FILE"
source "$RUNTIME_FILE"
set +a
[[ -x "$CLOUDFLARED_BIN" ]] || fail "cloudflared not found: $CLOUDFLARED_BIN"
[[ -n "${CLOUDFLARE_API_TOKEN:-}" && -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]] || fail 'Cloudflare API credentials are missing'
[[ -n "${CLOUDFLARE_ZONE_NAME:-}" && -n "${PUBLIC_HOSTNAME:-}" && -n "${DIRECT_HOSTNAME:-}" ]] || fail 'Cloudflare host configuration is incomplete'

api(){ local method=$1 url=$2 body=${3:-}; if [[ -n "$body" ]]; then curl -fsS -X "$method" "$url" -H 'Content-Type: application/json' -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" --data "$body"; else curl -fsS -X "$method" "$url" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"; fi; }

state_id=''; state_secret=''; state_account=''; tunnel_name=${CLOUDFLARE_TUNNEL_NAME:-echo-gateway}
if [[ -f "$STATE_FILE" ]]; then
  set -a; source "$STATE_FILE"; set +a
  state_id=${CLOUDFLARE_TUNNEL_ID:-}; state_secret=${CLOUDFLARE_TUNNEL_SECRET:-}; state_account=${CLOUDFLARE_TUNNEL_ACCOUNT_TAG:-}; tunnel_name=${CLOUDFLARE_TUNNEL_NAME:-$tunnel_name}
fi

if [[ "$DRY_RUN" == 1 ]]; then
  state_id=${state_id:-00000000-0000-4000-8000-000000000000}; state_secret=${state_secret:-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=}; state_account=${state_account:-$CLOUDFLARE_ACCOUNT_ID}
else
  if [[ -n "$state_id" && -n "$state_secret" ]]; then
    info=$(api GET "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$state_id") || fail 'stored tunnel cannot be read'
    python3 - "$info" "$state_account" "$tunnel_name" <<'PY'
import json,sys
r=json.loads(sys.argv[1]).get('result') or {}
if r.get('config_src') != 'local': raise SystemExit('stored tunnel is not locally managed')
if sys.argv[2] and r.get('account_tag') != sys.argv[2]: raise SystemExit('stored tunnel account mismatch')
if sys.argv[3] and r.get('name') != sys.argv[3]: raise SystemExit('stored tunnel name mismatch')
PY
    account_tag=$state_account
  else
    state_secret=$(openssl rand -base64 32 | tr -d '\n')
    body=$(TUNNEL_NAME="$tunnel_name" TUNNEL_SECRET="$state_secret" python3 - <<'PY'
import json,os
print(json.dumps({'name':os.environ['TUNNEL_NAME'],'config_src':'local','tunnel_secret':os.environ['TUNNEL_SECRET']}))
PY
)
    response=$(api POST "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel" "$body") || fail 'failed to create local-managed tunnel'
    read -r state_id account_tag cloud_name <<EOF
$(python3 - "$response" <<'PY'
import json,sys
r=json.loads(sys.argv[1]).get('result') or {}
print(r.get('id',''),r.get('account_tag',''),r.get('name',''))
PY
)
EOF
    [[ -n "$state_id" && -n "$account_tag" ]] || fail 'Cloudflare did not return tunnel identity'
    tunnel_name=${cloud_name:-$tunnel_name}
    install -d -m 0700 "$(dirname "$STATE_FILE")"
    umask 077
    cat > "$STATE_FILE" <<EOF
CLOUDFLARE_TUNNEL_ID=$state_id
CLOUDFLARE_TUNNEL_ACCOUNT_TAG=$account_tag
CLOUDFLARE_TUNNEL_NAME=$tunnel_name
CLOUDFLARE_TUNNEL_SECRET=$state_secret
EOF
    chmod 0600 "$STATE_FILE"
  fi
fi

export CLOUDFLARED_TUNNEL_ID=$state_id CLOUDFLARED_CREDENTIALS_PATH=$CREDENTIALS_PATH CLOUDFLARED_CONFIG_PATH=$CONFIG_PATH CLOUDFLARE_TUNNEL_ACCOUNT_TAG=${account_tag:-$state_account} CLOUDFLARE_TUNNEL_NAME=$tunnel_name

render(){
  python3 - "$1" "$2" <<'PY'
import os,re,sys
src,dst=sys.argv[1:]; text=open(src).read(); missing=[]
def repl(m):
  k=m.group(1); v=os.environ.get(k)
  if v is None: missing.append(k); return m.group(0)
  return v
text=re.sub(r'\$\{([A-Z][A-Z0-9_]*)\}',repl,text)
if missing: raise SystemExit('unresolved variables: '+', '.join(sorted(set(missing))))
open(dst,'w').write(text)
PY
}

install -d -m 0755 "$(dirname "$CONFIG_PATH")"
if [[ "$DRY_RUN" == 0 ]]; then
  printf '{"AccountTag":"%s","TunnelSecret":"%s","TunnelID":"%s"}\n' "$account_tag" "$state_secret" "$state_id" > "$CREDENTIALS_PATH.tmp"
  chmod 0600 "$CREDENTIALS_PATH.tmp"; mv "$CREDENTIALS_PATH.tmp" "$CREDENTIALS_PATH"
fi
render "$TEMPLATE" "$CONFIG_PATH.tmp"
render "$SERVICE_TEMPLATE" "$SERVICE_PATH.tmp"
"$CLOUDFLARED_BIN" --config "$CONFIG_PATH.tmp" tunnel ingress validate

if [[ "$DRY_RUN" == 1 ]]; then rm -f "$CONFIG_PATH.tmp" "$SERVICE_PATH.tmp"; printf '%s\n' 'cloudflare: dry-run validation succeeded; no local or remote state changed'; exit 0; fi

zone_json=$(api GET "$CF_API/zones?name=$CLOUDFLARE_ZONE_NAME&status=active") || fail 'failed to query Cloudflare zone'
zone_id=$(python3 - "$zone_json" <<'PY'
import json,sys
r=json.loads(sys.argv[1]).get('result') or []
print(r[0].get('id','') if r else '')
PY
)
[[ -n "$zone_id" ]] || fail 'zone not found or token lacks access'
server_ipv4=${PUBLIC_IPV4:-}
[[ -n "$server_ipv4" ]] || server_ipv4=$(curl -4 -fsS https://api.ipify.org || true)
[[ "$server_ipv4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail 'could not determine public IPv4'

ensure_dns(){
  local name=$1 type=$2 content=$3 proxied=$4 ttl=$5
  local data rid rtype rcontent rproxy
  data=$(api GET "$CF_API/zones/$zone_id/dns_records?name=$name") || fail "failed to inspect DNS record: $name"
  read -r rid rtype rcontent rproxy <<EOF
$(python3 - "$data" <<'PY'
import json,sys
r=json.loads(sys.argv[1]).get('result') or []
x=r[0] if r else {}
print(x.get('id',''),x.get('type',''),x.get('content',''),x.get('proxied',False))
PY
)
EOF
  if [[ -n "$rid" ]]; then
    [[ "$rtype" == "$type" && "$rcontent" == "$content" && "$rproxy" == "$proxied" ]] || fail "existing DNS record for $name conflicts with gateway"
  else
    body=$(python3 - "$name" "$type" "$content" "$proxied" "$ttl" <<'PY'
import json,sys
print(json.dumps({'name':sys.argv[1],'type':sys.argv[2],'content':sys.argv[3],'proxied':sys.argv[4]=='true','ttl':int(sys.argv[5])}))
PY
)
    api POST "$CF_API/zones/$zone_id/dns_records" "$body" >/dev/null || fail "failed to create DNS record: $name"
  fi
}

ensure_dns "$PUBLIC_HOSTNAME" CNAME "$state_id.cfargotunnel.com" true 1
ensure_dns "$DIRECT_HOSTNAME" A "$server_ipv4" false 300

chmod 0600 "$CONFIG_PATH.tmp"; chmod 0644 "$SERVICE_PATH.tmp"
install -m 0600 "$CONFIG_PATH.tmp" "$CONFIG_PATH"
install -m 0644 "$SERVICE_PATH.tmp" "$SERVICE_PATH"
rm -f "$CONFIG_PATH.tmp" "$SERVICE_PATH.tmp"
systemctl daemon-reload
systemctl enable --now cloudflared-echo.service
systemctl --quiet is-active cloudflared-echo.service || fail 'cloudflared-echo.service is not active'
printf 'cloudflare: tunnel active (%s), DNS ready (%s, %s)\n' "$state_id" "$PUBLIC_HOSTNAME" "$DIRECT_HOSTNAME"
