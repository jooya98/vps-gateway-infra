#!/usr/bin/env bash
set -euo pipefail

fail(){ printf 'cloudflared-local: %s\n' "$1" >&2; exit 1; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
PROFILE_FILE=${PROFILE_FILE:-$ROOT/config/profiles/gateway-diverse.env.example}
STATE_FILE=${STATE_FILE:-/root/vps-gateway-cloudflared.conf}
CONFIG_PATH=${CLOUDFLARED_CONFIG_PATH:-/etc/cloudflared/echo-config.yml}
CREDENTIALS_PATH=${CLOUDFLARED_CREDENTIALS_PATH:-/etc/cloudflared/echo-tunnel.json}
SERVICE_PATH=${SERVICE_PATH:-/etc/systemd/system/cloudflared-echo.service}
TEMPLATE=${TEMPLATE:-$ROOT/templates/cloudflared/multiprotocol-config.yml.tmpl}
SERVICE_TEMPLATE=${SERVICE_TEMPLATE:-$ROOT/templates/cloudflared/multiprotocol.service.tmpl}
CF_API=${CF_API:-https://api.cloudflare.com/client/v4}
DRY_RUN=${DRY_RUN:-0}

[[ $EUID -eq 0 ]] || fail 'root is required'
command -v curl >/dev/null 2>&1 || fail 'curl is required'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
command -v openssl >/dev/null 2>&1 || fail 'openssl is required'
[[ -x "${CLOUDFLARED_BIN:-/usr/local/bin/cloudflared}" ]] || fail 'cloudflared not found'
[[ -f "$RUNTIME_FILE" && -f "$PROFILE_FILE" ]] || fail 'runtime/profile file missing'
[[ -f "$TEMPLATE" && -f "$SERVICE_TEMPLATE" ]] || fail 'Cloudflare templates missing'

set -a
source "$RUNTIME_FILE"
source "$PROFILE_FILE"
set +a
[[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] || fail 'CLOUDFLARE_API_TOKEN is required for local-managed provisioning'
[[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]] || fail 'CLOUDFLARE_ACCOUNT_ID is required'
[[ -n "${CLOUDFLARE_ZONE_NAME:-}" ]] || fail 'CLOUDFLARE_ZONE_NAME is required'
[[ -n "${PUBLIC_HOSTNAME:-}" ]] || fail 'PUBLIC_HOSTNAME is required'

state_id=''; state_secret=''; state_account=''; tunnel_name="${CLOUDFLARE_TUNNEL_NAME:-echo-gateway}"
if [[ -f "$STATE_FILE" ]]; then
  set -a; source "$STATE_FILE"; set +a
  state_id=${CLOUDFLARE_TUNNEL_ID:-}
  state_secret=${CLOUDFLARE_TUNNEL_SECRET:-}
  state_account=${CLOUDFLARE_TUNNEL_ACCOUNT_TAG:-}
  tunnel_name=${CLOUDFLARE_TUNNEL_NAME:-$tunnel_name}
fi

api(){
  local method=$1 url=$2 body=${3:-}
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" "$url" -H 'Content-Type: application/json' -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" --data "$body"
  else
    curl -fsS -X "$method" "$url" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
  fi
}

if [[ "$DRY_RUN" == 1 ]]; then
  # Do not create/modify Cloudflare resources during dry-run. A stored local
  # tunnel may be inspected; otherwise use a syntactically valid placeholder
  # UUID and validate only the generated local config/service.
  if [[ -z "$state_id" ]]; then
    state_id=00000000-0000-4000-8000-000000000000
    state_account="${CLOUDFLARE_ACCOUNT_ID}"
  fi
  state_secret=${state_secret:-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=}
  account_tag=${state_account:-$CLOUDFLARE_ACCOUNT_ID}
else
  if [[ -n "$state_id" && -n "$state_secret" ]]; then
    info=$(api GET "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$state_id") || fail 'stored tunnel cannot be read'
    read -r config_src account_tag cloud_name <<EOF
$(python3 - <<'PY' "$info"
import json,sys
r=json.loads(sys.argv[1]).get('result') or {}
print(r.get('config_src',''), r.get('account_tag',''), r.get('name',''))
PY
)
EOF
    [[ "$config_src" == local ]] || fail "stored tunnel is not locally managed (config_src=$config_src)"
    [[ -z "$state_account" || "$state_account" == "$account_tag" ]] || fail 'stored tunnel account tag mismatch'
    [[ -z "$cloud_name" || "$cloud_name" == "$tunnel_name" ]] || tunnel_name=$cloud_name
  else
    state_secret=$(openssl rand -base64 32 | tr -d '\n')
    body=$(TUNNEL_SECRET="$state_secret" TUNNEL_NAME="$tunnel_name" python3 - <<'PY'
import json,os
print(json.dumps({'name':os.environ['TUNNEL_NAME'],'config_src':'local','tunnel_secret':os.environ['TUNNEL_SECRET']}))
PY
    )
    response=$(api POST "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel" "$body") || fail 'failed to create locally-managed tunnel'
    read -r state_id account_tag cloud_name <<EOF
$(python3 - <<'PY' "$response"
import json,sys
r=json.loads(sys.argv[1]).get('result') or {}
print(r.get('id',''), r.get('account_tag',''), r.get('name',''))
PY
)
EOF
    [[ -n "$state_id" && -n "$account_tag" ]] || fail 'Cloudflare did not return tunnel identity'
    tunnel_name=${cloud_name:-$tunnel_name}
    install -d -m 0700 "$(dirname "$STATE_FILE")"
    umask 077
    cat > "$STATE_FILE" <<EOF
# Local-managed Cloudflare tunnel state. Mode 0600.
CLOUDFLARE_TUNNEL_ID=$state_id
CLOUDFLARE_TUNNEL_ACCOUNT_TAG=$account_tag
CLOUDFLARE_TUNNEL_NAME=$tunnel_name
CLOUDFLARE_TUNNEL_SECRET=$state_secret
EOF
    chmod 0600 "$STATE_FILE"
  fi
fi

export CLOUDFLARED_TUNNEL_ID=$state_id
export CLOUDFLARED_CREDENTIALS_PATH=$CREDENTIALS_PATH
export CLOUDFLARED_CONFIG_PATH=$CONFIG_PATH
export CLOUDFLARE_TUNNEL_ACCOUNT_TAG=${account_tag:-$state_account}
export CLOUDFLARE_TUNNEL_NAME=$tunnel_name

render(){
  python3 - "$1" "$2" <<'PY'
import os,re,sys
src,dst=sys.argv[1:]
text=open(src).read(); missing=[]
def repl(m):
    k=m.group(1)
    if k not in os.environ:
        missing.append(k); return m.group(0)
    return os.environ[k]
text=re.sub(r'\$\{([A-Z][A-Z0-9_]*)\}',repl,text)
if missing: raise SystemExit('cloudflared-local: unresolved variables: '+', '.join(sorted(set(missing))))
open(dst,'w').write(text)
PY
}

install -d -m 0755 "$(dirname "$CONFIG_PATH")" "$(dirname "$SERVICE_PATH")"
if [[ "$DRY_RUN" == 0 ]]; then
  cat > "$CREDENTIALS_PATH.tmp" <<EOF
{"AccountTag":"$account_tag","TunnelSecret":"$state_secret","TunnelID":"$state_id"}
EOF
  chmod 0600 "$CREDENTIALS_PATH.tmp"
  mv "$CREDENTIALS_PATH.tmp" "$CREDENTIALS_PATH"
fi

render "$TEMPLATE" "$CONFIG_PATH.tmp"
render "$SERVICE_TEMPLATE" "$SERVICE_PATH.tmp"
"${CLOUDFLARED_BIN:-/usr/local/bin/cloudflared}" --config "$CONFIG_PATH.tmp" tunnel ingress validate

if [[ "$DRY_RUN" == 0 ]]; then
  zone_json=$(api GET "$CF_API/zones?name=$CLOUDFLARE_ZONE_NAME&status=active") || fail 'failed to query Cloudflare zone'
  zone_id=$(python3 - <<'PY' "$zone_json"
import json,sys
r=json.loads(sys.argv[1]).get('result') or []
print(r[0].get('id','') if r else '')
PY
  )
  [[ -n "$zone_id" ]] || fail 'zone was not found or token lacks zone access'
  records=$(api GET "$CF_API/zones/$zone_id/dns_records?name=$PUBLIC_HOSTNAME") || fail 'failed to inspect DNS record'
  read -r record_id record_type record_content <<EOF
$(python3 - <<'PY' "$records"
import json,sys
r=json.loads(sys.argv[1]).get('result') or []
if not r: print('')
else:
 x=r[0]; print(x.get('id',''),x.get('type',''),x.get('content',''))
PY
)
EOF
  expected="$state_id.cfargotunnel.com"
  if [[ -n "$record_id" ]]; then
    [[ "$record_type" == CNAME && "$record_content" == "$expected" ]] || fail "existing DNS record for $PUBLIC_HOSTNAME is not the expected tunnel CNAME"
  else
    EXPECTED="$expected" python3 - <<'PY' > "$CONFIG_PATH.dns.json"
import json,os
print(json.dumps({'type':'CNAME','name':os.environ['PUBLIC_HOSTNAME'],'content':os.environ['EXPECTED'],'ttl':1,'proxied':True}))
PY
    dns_body=$(cat "$CONFIG_PATH.dns.json"); rm -f "$CONFIG_PATH.dns.json"
    api POST "$CF_API/zones/$zone_id/dns_records" "$dns_body" >/dev/null || fail 'failed to create DNS CNAME'
  fi

  chmod 0600 "$CONFIG_PATH.tmp"; chmod 0644 "$SERVICE_PATH.tmp"
  install -m 0600 "$CONFIG_PATH.tmp" "$CONFIG_PATH"
  install -m 0644 "$SERVICE_PATH.tmp" "$SERVICE_PATH"
  rm -f "$CONFIG_PATH.tmp" "$SERVICE_PATH.tmp"
  systemctl daemon-reload
  systemctl enable --now cloudflared-echo.service
  systemctl --quiet is-active cloudflared-echo.service || fail 'cloudflared service did not become active'
  printf 'cloudflared-local: local-managed tunnel active (%s)\n' "$state_id"
else
  rm -f "$CONFIG_PATH.tmp" "$SERVICE_PATH.tmp"
  printf 'cloudflared-local: dry-run validation succeeded; Cloudflare and local service state unchanged\n'
fi
