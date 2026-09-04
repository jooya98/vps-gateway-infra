#!/usr/bin/env bash
set -euo pipefail

# Additive activation path for an already-provisioned Echo VPS.
# Unlike bootstrap/deploy, this script does not install packages, change SSH,
# change UFW, or touch the Cloudflare Tunnel service. It only validates and
# atomically swaps the sing-box configuration, preserving the existing
# Reality/legacy-Shadowsocks/SOCKS listeners where possible.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
MULTI_RUNTIME_FILE=${MULTI_RUNTIME_FILE:-/root/vps-gateway-multiprotocol.conf}
CONFIG_FILE=${CONFIG_FILE:-/etc/sing-box/config.json}
BACKUP_DIR=${BACKUP_DIR:-/etc/sing-box/backups}
SING_BOX_BIN=${SING_BOX_BIN:-/usr/local/bin/sing-box}
PROFILE_FILE=${PROFILE_FILE:-"$ROOT/config/profiles/gateway-diverse.env.example"}
TEMPLATE_FILE=${TEMPLATE_FILE:-"$ROOT/templates/sing-box/multiprotocol.json.tmpl"}
DRY_RUN=${DRY_RUN:-0}

[[ "$(id -u)" == 0 ]] || { printf 'activate: root is required\n' >&2; exit 1; }
[[ -x "$SING_BOX_BIN" ]] || { printf 'activate: sing-box not found: %s\n' "$SING_BOX_BIN" >&2; exit 1; }
[[ -f "$RUNTIME_FILE" ]] || { printf 'activate: existing runtime file not found: %s\n' "$RUNTIME_FILE" >&2; exit 1; }
[[ -f "$CONFIG_FILE" ]] || { printf 'activate: current sing-box config not found: %s\n' "$CONFIG_FILE" >&2; exit 1; }
[[ -f "$PROFILE_FILE" && -f "$TEMPLATE_FILE" ]] || { printf 'activate: profile/template missing\n' >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$RUNTIME_FILE"
# shellcheck disable=SC1090
source "$PROFILE_FILE"
if [[ -f "$MULTI_RUNTIME_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$MULTI_RUNTIME_FILE"
fi
set +a

# Preserve the live listener choices from the currently deployed config.
eval "$(python3 - "$CONFIG_FILE" <<'PY'
import json, shlex, sys
p=sys.argv[1]
with open(p) as f: c=json.load(f)

def find(tag):
    for x in c.get('inbounds',[]):
        if x.get('tag') == tag:
            return x
    return None
r=find('vless-reality')
if not r:
    for x in c.get('inbounds',[]):
        if x.get('type')=='vless' and x.get('tls',{}).get('reality',{}).get('enabled'):
            r=x; break
ss=find('shadowsocks-in') or find('shadowsocks')
socks=find('socks-in') or find('socks-out') or find('socks5')
for k,v in {
    'REALITY_LISTEN_ADDRESS': (r or {}).get('listen','::'),
    'REALITY_PORT': (r or {}).get('listen_port',8443),
    'SHADOWSOCKS_LISTEN_ADDRESS': (ss or {}).get('listen','::'),
    'SHADOWSOCKS_PORT': (ss or {}).get('listen_port',8444),
    'SOCKS_LISTEN_ADDRESS': (socks or {}).get('listen','127.0.0.1'),
    'SOCKS_LISTEN_PORT': (socks or {}).get('listen_port',1080),
}.items():
    print(f'{k}={shlex.quote(str(v))}')
PY
)"

# Generate additive protocol secrets once. Existing credentials are never rotated.
if [[ ! -f "$MULTI_RUNTIME_FILE" ]]; then
  command -v openssl >/dev/null 2>&1 || { printf 'activate: openssl is required\n' >&2; exit 1; }
  multi_dir=$(dirname "$MULTI_RUNTIME_FILE")
  install -d -m 0700 "$multi_dir"
  tmp=$(mktemp "$multi_dir/.vps-gateway-multiprotocol.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  TUI_UUID=$("$SING_BOX_BIN" generate uuid 2>/dev/null || true)
  [[ -n "$TUI_UUID" ]] || TUI_UUID=$(cat /proc/sys/kernel/random/uuid)
  cat > "$tmp" <<EOF
# Generated once for Echo's additive multi-protocol layer. Keep mode 0600.
MULTI_SHADOWSOCKS_PASSWORD=$(openssl rand -hex 24)
MULTI_SHADOWSOCKS_2022_PASSWORD=$(openssl rand -base64 32)
MULTI_HYSTERIA2_PASSWORD=$(openssl rand -hex 32)
MULTI_TUIC_UUID=$TUI_UUID
MULTI_TUIC_PASSWORD=$(openssl rand -hex 32)
MULTI_TROJAN_PASSWORD=$(openssl rand -hex 32)
MULTI_ANYTLS_PASSWORD=$(openssl rand -hex 32)
EOF
  chown root:root "$tmp"
  chmod 0600 "$tmp"
  mv "$tmp" "$MULTI_RUNTIME_FILE"
  trap - EXIT
  set -a
  # shellcheck disable=SC1090
  source "$MULTI_RUNTIME_FILE"
  set +a
fi

required=(VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID SOCKS_USERNAME SOCKS_PASSWORD SHADOWSOCKS_PASSWORD MULTI_SHADOWSOCKS_2022_PASSWORD)
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || { printf 'activate: missing runtime value: %s\n' "$name" >&2; exit 1; }
done

DIRECT_TLS_INBOUNDS=''
if [[ "${ENABLE_DIRECT_TLS:-0}" == "1" ]]; then
  [[ -r "${TLS_CERT_PATH:-}" && -r "${TLS_KEY_PATH:-}" ]] || {
    printf 'activate: ENABLE_DIRECT_TLS=1 requires readable TLS_CERT_PATH and TLS_KEY_PATH\n' >&2
    exit 1
  }
  DIRECT_TLS_INBOUNDS=$(python3 - <<'PY'
import json, os
cert=os.environ['TLS_CERT_PATH']; key=os.environ['TLS_KEY_PATH']; name=os.environ['TLS_SERVER_NAME']
def tls(alpn=None):
    d={'enabled':True,'server_name':name,'certificate_path':cert,'key_path':key}
    if alpn: d['alpn']=alpn
    return d
items=[
 {'type':'hysteria2','tag':'hysteria2','listen':'::','listen_port':int(os.environ['HYSTERIA2_PORT']),'users':[{'name':'personal','password':os.environ['MULTI_HYSTERIA2_PASSWORD']}],'tls':tls()},
 {'type':'tuic','tag':'tuic','listen':'::','listen_port':int(os.environ['TUIC_PORT']),'users':[{'name':'personal','uuid':os.environ['MULTI_TUIC_UUID'],'password':os.environ['MULTI_TUIC_PASSWORD']}],'congestion_control':'bbr','zero_rtt_handshake':False,'heartbeat':'10s','tls':tls()},
 {'type':'trojan','tag':'trojan','listen':'::','listen_port':int(os.environ['TROJAN_PORT']),'users':[{'name':'personal','password':os.environ['MULTI_TROJAN_PASSWORD']}],'tls':tls(['h2','http/1.1']),'multiplex':{'enabled':True}},
 {'type':'anytls','tag':'anytls','listen':'::','listen_port':int(os.environ['ANYTLS_PORT']),'users':[{'name':'personal','password':os.environ['MULTI_ANYTLS_PASSWORD']}],'tls':tls()},
 {'type':'vless','tag':'vless-grpc','listen':'::','listen_port':int(os.environ['VLESS_GRPC_PORT']),'users':[{'name':'personal','uuid':os.environ['VLESS_UUID']}],'tls':tls(['h2']),'transport':{'type':'grpc','service_name':'EchoService'}},
]
print(','+json.dumps(items,separators=(',',':'))[1:])
PY
)
fi

export DIRECT_TLS_INBOUNDS
rendered=$(mktemp /etc/sing-box/.multiprotocol.XXXXXX)
backup=""
cleanup(){ rm -f "$rendered"; }
trap cleanup EXIT

python3 - "$TEMPLATE_FILE" "$rendered" <<'PY'
import os,re,sys
src,dst=sys.argv[1:]
text=open(src).read()
pat=re.compile(r'\$\{([A-Z][A-Z0-9_]*)\}')
missing=[]
def repl(m):
    k=m.group(1)
    if k not in os.environ:
        missing.append(k); return m.group(0)
    return os.environ[k]
text=pat.sub(repl,text)
if missing:
    raise SystemExit('activate: unresolved variables: '+', '.join(sorted(set(missing))))
open(dst,'w').write(text)
PY
chmod 0600 "$rendered"

"$SING_BOX_BIN" check -c "$rendered"

if [[ "$DRY_RUN" == 1 ]]; then
  printf '%s\n' 'activate: dry-run validation succeeded; live configuration unchanged'
  exit 0
fi

install -d -m 0700 "$BACKUP_DIR"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$BACKUP_DIR/config.json.$timestamp"
cp -a "$CONFIG_FILE" "$backup"
chmod 0600 "$backup"

install -m 0600 "$rendered" "$CONFIG_FILE"
if systemctl restart sing-box.service && systemctl --quiet is-active sing-box.service; then
  printf 'activate: multi-protocol configuration active\n'
  printf 'activate: previous configuration backup: %s\n' "$backup"
else
  printf '%s\n' 'activate: new configuration failed to start; restoring previous configuration' >&2
  cp -a "$backup" "$CONFIG_FILE"
  chmod 0600 "$CONFIG_FILE"
  systemctl restart sing-box.service || true
  exit 1
fi
