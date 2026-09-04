#!/usr/bin/env bash
set -euo pipefail

# Internal helper invoked by the single deploy path.
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

set -a
source "$ROOT/config/defaults.env.example"
source "$PROFILE_FILE"
source "$RUNTIME_FILE"
[[ -f "$MULTI_RUNTIME_FILE" ]] && source "$MULTI_RUNTIME_FILE"
set +a

# A fresh VPS has no live config yet. Existing config remains the source of truth
# for preserved Reality/SOCKS/Shadowsocks credentials when available.
if [[ -f "$CONFIG_FILE" ]]; then
  set -a
  eval "$(python3 - "$CONFIG_FILE" <<'PY'
import json,shlex,sys
c=json.load(open(sys.argv[1]))
def find(tags): return next((x for x in c.get('inbounds',[]) if x.get('tag') in tags),None)
def user(x): return ((x or {}).get('users') or [{}])[0]
r=find(['vless-reality']) or next((x for x in c.get('inbounds',[]) if x.get('type')=='vless' and x.get('tls',{}).get('reality',{}).get('enabled')),None)
ss=find(['shadowsocks','shadowsocks-in']); socks=find(['socks5','socks-in'])
vals={
'REALITY_LISTEN_ADDRESS':(r or {}).get('listen','0.0.0.0'),'REALITY_PORT':(r or {}).get('listen_port',8443),
'REALITY_SERVER_NAME':(r or {}).get('tls',{}).get('server_name','www.cloudflare.com'),'REALITY_HANDSHAKE_SERVER':(r or {}).get('tls',{}).get('reality',{}).get('handshake',{}).get('server','www.cloudflare.com'),'REALITY_HANDSHAKE_PORT':(r or {}).get('tls',{}).get('reality',{}).get('handshake',{}).get('server_port',443),'REALITY_PRIVATE_KEY':(r or {}).get('tls',{}).get('reality',{}).get('private_key',''),'REALITY_SHORT_ID':((r or {}).get('tls',{}).get('reality',{}).get('short_id') or [''])[0],'VLESS_UUID':user(r).get('uuid',''),'SHADOWSOCKS_LISTEN_ADDRESS':(ss or {}).get('listen','0.0.0.0'),'SHADOWSOCKS_PORT':(ss or {}).get('listen_port',8444),'SHADOWSOCKS_PASSWORD':(ss or {}).get('password','') or user(ss).get('password',''),'SOCKS_LISTEN_ADDRESS':(socks or {}).get('listen','0.0.0.0'),'SOCKS_LISTEN_PORT':(socks or {}).get('listen_port',1080),'SOCKS_USERNAME':user(socks).get('username',''),'SOCKS_PASSWORD':user(socks).get('password','')}
for k,v in vals.items(): print(f'{k}={shlex.quote(str(v))}')
PY
)"
  set +a
fi

# Fresh installs use generated bootstrap credentials directly.
: "${VLESS_UUID:=${VLESS_UUID:-}}"
: "${REALITY_PRIVATE_KEY:=${REALITY_PRIVATE_KEY:-}}"
: "${REALITY_SHORT_ID:=${REALITY_SHORT_ID:-}}"
: "${SOCKS_USERNAME:=${SOCKS_USERNAME:-gateway}}"
: "${SOCKS_PASSWORD:=${SOCKS_PASSWORD:-}}"
: "${SHADOWSOCKS_PASSWORD:=${TRANSPORT_PASSWORD:-}}"
for name in VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID SOCKS_USERNAME SOCKS_PASSWORD SHADOWSOCKS_PASSWORD; do [[ -n "${!name:-}" ]] || fail "missing credential: $name"; done

if [[ ! -f "$MULTI_RUNTIME_FILE" ]]; then
  install -d -m 0700 "$(dirname "$MULTI_RUNTIME_FILE")"
  tmp=$(mktemp "$(dirname "$MULTI_RUNTIME_FILE")/.multiprotocol.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
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
export DIRECT_TLS_INBOUNDS

rendered=$(mktemp /etc/sing-box/.multiprotocol.XXXXXX)
trap 'rm -f "$rendered"' EXIT
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

install -d -m 0755 /etc/systemd/system "$BACKUP_DIR"
if [[ -f /etc/systemd/system/sing-box.service && -f "$CONFIG_FILE" ]]; then
  timestamp=$(date -u +%Y%m%dT%H%M%SZ); backup="$BACKUP_DIR/config.json.$timestamp"; cp -a "$CONFIG_FILE" "$backup"; chmod 0600 "$backup"
fi
install -m 0600 "$rendered" "$CONFIG_FILE"
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$SING_BOX_BIN run -c $CONFIG_FILE
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/sing-box.service
systemctl daemon-reload
if systemctl enable --now sing-box.service && systemctl --quiet is-active sing-box.service; then
 printf '%s\n' 'gateway-config: complete multi-protocol configuration active'
else
 if [[ -n "${backup:-}" && -f "$backup" ]]; then cp -a "$backup" "$CONFIG_FILE"; chmod 0600 "$CONFIG_FILE"; systemctl restart sing-box.service || true; fi
 fail 'sing-box failed to start; previous configuration restored when available'
fi
