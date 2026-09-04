#!/usr/bin/env bash
set -euo pipefail

# Internal helper invoked by deploy.sh. It is not a separate installation step.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
MULTI_RUNTIME_FILE=${MULTI_RUNTIME_FILE:-/root/vps-gateway-multiprotocol.conf}
CONFIG_FILE=${CONFIG_FILE:-/etc/sing-box/config.json}
BACKUP_DIR=${BACKUP_DIR:-/etc/sing-box/backups}
SING_BOX_BIN=${SING_BOX_BIN:-/usr/local/bin/sing-box}
PROFILE_FILE=${PROFILE_FILE:-"$ROOT/config/profiles/gateway.env.example"}
TEMPLATE_FILE=${TEMPLATE_FILE:-"$ROOT/templates/sing-box/multiprotocol.json.tmpl"}
DRY_RUN=${DRY_RUN:-0}

fail(){ printf 'gateway-config: %s\n' "$1" >&2; exit 1; }
[[ $(id -u) == 0 ]] || fail 'root is required'
[[ -x "$SING_BOX_BIN" ]] || fail "sing-box not found: $SING_BOX_BIN"
[[ -f "$RUNTIME_FILE" && -f "$PROFILE_FILE" && -f "$TEMPLATE_FILE" ]] || fail 'runtime/profile/template missing'
[[ -f "$CONFIG_FILE" ]] || fail 'current sing-box config not found'

set -a
source "$ROOT/config/defaults.env.example"
source "$RUNTIME_FILE"
source "$PROFILE_FILE"
[[ -f "$MULTI_RUNTIME_FILE" ]] && source "$MULTI_RUNTIME_FILE"
set +a

set -a
eval "$(python3 - "$CONFIG_FILE" <<'PY'
import json, shlex, sys
c=json.load(open(sys.argv[1]))
def find(tag):
    return next((x for x in c.get('inbounds',[]) if x.get('tag')==tag),None)
def user(x): return ((x or {}).get('users') or [{}])[0]
r=find('vless-reality') or next((x for x in c.get('inbounds',[]) if x.get('type')=='vless' and x.get('tls',{}).get('reality',{}).get('enabled')),None)
ss=find('shadowsocks') or find('shadowsocks-in')
socks=find('socks5') or find('socks-in')
vals={
 'REALITY_LISTEN_ADDRESS':(r or {}).get('listen','0.0.0.0'),'REALITY_PORT':(r or {}).get('listen_port',8443),
 'REALITY_SERVER_NAME':(r or {}).get('tls',{}).get('server_name','www.cloudflare.com'),
 'REALITY_HANDSHAKE_SERVER':(r or {}).get('tls',{}).get('reality',{}).get('handshake',{}).get('server','www.cloudflare.com'),
 'REALITY_HANDSHAKE_PORT':(r or {}).get('tls',{}).get('reality',{}).get('handshake',{}).get('server_port',443),
 'REALITY_PRIVATE_KEY':(r or {}).get('tls',{}).get('reality',{}).get('private_key',''),
 'REALITY_SHORT_ID':((r or {}).get('tls',{}).get('reality',{}).get('short_id') or [''])[0],
 'VLESS_UUID':user(r).get('uuid',''),'SHADOWSOCKS_LISTEN_ADDRESS':(ss or {}).get('listen','0.0.0.0'),
 'SHADOWSOCKS_PORT':(ss or {}).get('listen_port',8444),'SHADOWSOCKS_PASSWORD':(ss or {}).get('password','') or user(ss).get('password',''),
 'SOCKS_LISTEN_ADDRESS':(socks or {}).get('listen','0.0.0.0'),'SOCKS_LISTEN_PORT':(socks or {}).get('listen_port',1080),
 'SOCKS_USERNAME':user(socks).get('username',''),'SOCKS_PASSWORD':user(socks).get('password','')}
for k,v in vals.items(): print(f'{k}={shlex.quote(str(v))}')
PY
)"
set +a

if [[ ! -f "$MULTI_RUNTIME_FILE" ]]; then
  multi_dir=$(dirname "$MULTI_RUNTIME_FILE"); install -d -m 0700 "$multi_dir"; tmp=$(mktemp "$multi_dir/.vps-gateway-multiprotocol.XXXXXX"); trap 'rm -f "$tmp"' EXIT
  TUI_UUID=$("$SING_BOX_BIN" generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  cat > "$tmp" <<EOF
MULTI_SHADOWSOCKS_PASSWORD=$(openssl rand -hex 24)
MULTI_SHADOWSOCKS_2022_PASSWORD=$(openssl rand -base64 32)
MULTI_HYSTERIA2_PASSWORD=$(openssl rand -hex 32)
MULTI_TUIC_UUID=$TUI_UUID
MULTI_TUIC_PASSWORD=$(openssl rand -hex 32)
MULTI_TROJAN_PASSWORD=$(openssl rand -hex 32)
MULTI_ANYTLS_PASSWORD=$(openssl rand -hex 32)
EOF
  chown root:root "$tmp"; chmod 0600 "$tmp"; mv "$tmp" "$MULTI_RUNTIME_FILE"; trap - EXIT
  set -a; source "$MULTI_RUNTIME_FILE"; set +a
fi

for name in VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID SOCKS_USERNAME SOCKS_PASSWORD SHADOWSOCKS_PASSWORD MULTI_SHADOWSOCKS_2022_PASSWORD; do
  [[ -n "${!name:-}" ]] || fail "missing credential: $name"
done

DIRECT_TLS_INBOUNDS=''
if [[ "$ENABLE_DIRECT_TLS" == 1 ]]; then
  [[ -r "$TLS_CERT_PATH" && -r "$TLS_KEY_PATH" ]] || fail 'TLS certificate/key are missing'
  DIRECT_TLS_INBOUNDS=$(python3 - <<'PY'
import json,os
cert=os.environ['TLS_CERT_PATH']; key=os.environ['TLS_KEY_PATH']; name=os.environ['TLS_SERVER_NAME']
def tls(alpn=None):
 d={'enabled':True,'server_name':name,'certificate_path':cert,'key_path':key}
 if alpn: d['alpn']=alpn
 return d
items=[
 {'type':'hysteria2','tag':'hysteria2','listen':'0.0.0.0','listen_port':int(os.environ['HYSTERIA2_PORT']),'users':[{'name':'personal','password':os.environ['MULTI_HYSTERIA2_PASSWORD']}],'tls':tls()},
 {'type':'tuic','tag':'tuic','listen':'0.0.0.0','listen_port':int(os.environ['TUIC_PORT']),'users':[{'name':'personal','uuid':os.environ['MULTI_TUIC_UUID'],'password':os.environ['MULTI_TUIC_PASSWORD']}],'congestion_control':'bbr','zero_rtt_handshake':False,'heartbeat':'10s','tls':tls()},
 {'type':'trojan','tag':'trojan','listen':'0.0.0.0','listen_port':int(os.environ['TROJAN_PORT']),'users':[{'name':'personal','password':os.environ['MULTI_TROJAN_PASSWORD']}],'tls':tls(['h2','http/1.1']),'multiplex':{'enabled':True}},
 {'type':'anytls','tag':'anytls','listen':'0.0.0.0','listen_port':int(os.environ['ANYTLS_PORT']),'users':[{'name':'personal','password':os.environ['MULTI_ANYTLS_PASSWORD']}],'tls':tls()},
 {'type':'vless','tag':'vless-grpc','listen':'0.0.0.0','listen_port':int(os.environ['VLESS_GRPC_PORT']),'users':[{'name':'personal','uuid':os.environ['VLESS_UUID']}],'tls':tls(['h2']),'transport':{'type':'grpc','service_name':'EchoService'}}]
print(','+json.dumps(items,separators=(',',':'))[1:-1])
PY
)
fi
export DIRECT_TLS_INBOUNDS
rendered=$(mktemp /etc/sing-box/.multiprotocol.XXXXXX); trap 'rm -f "$rendered"' EXIT
python3 - "$TEMPLATE_FILE" "$rendered" <<'PY'
import os,re,sys
text=open(sys.argv[1]).read(); missing=[]
def repl(m):
 k=m.group(1); v=os.environ.get(k)
 if v is None: missing.append(k); return m.group(0)
 return v
text=re.sub(r'\$\{([A-Z][A-Z0-9_]*)\}',repl,text)
if missing: raise SystemExit('unresolved variables: '+', '.join(sorted(set(missing))))
open(sys.argv[2],'w').write(text)
PY
chmod 0600 "$rendered"
"$SING_BOX_BIN" check -c "$rendered"
if [[ "$DRY_RUN" == 1 ]]; then printf '%s\n' 'gateway-config: dry-run validation succeeded; live configuration unchanged'; exit 0; fi
install -d -m 0700 "$BACKUP_DIR"; timestamp=$(date -u +%Y%m%dT%H%M%SZ); backup="$BACKUP_DIR/config.json.$timestamp"; cp -a "$CONFIG_FILE" "$backup"; chmod 0600 "$backup"
install -m 0600 "$rendered" "$CONFIG_FILE"
if systemctl restart sing-box.service && systemctl --quiet is-active sing-box.service; then
 printf 'gateway-config: complete multi-protocol configuration active\n'
else
 printf '%s\n' 'gateway-config: new configuration failed; restoring previous configuration' >&2
 cp -a "$backup" "$CONFIG_FILE"; chmod 0600 "$CONFIG_FILE"; systemctl restart sing-box.service || true; exit 1
fi
