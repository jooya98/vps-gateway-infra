#!/usr/bin/env bash
set -euo pipefail

fail(){ printf 'client-bundle: %s\n' "$1" >&2; exit 1; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
MULTI_RUNTIME_FILE=${MULTI_RUNTIME_FILE:-/root/vps-gateway-multiprotocol.conf}
CONFIG_FILE=${CONFIG_FILE:-/etc/sing-box/config.json}
CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
PROFILE_FILE=${PROFILE_FILE:-$ROOT/config/profiles/gateway-diverse.env.example}
CLIENT_USER=${CLIENT_USER:-}

[[ $EUID -eq 0 ]] || fail 'run as root so the live config and secret stores can be read'
[[ -f "$RUNTIME_FILE" && -f "$MULTI_RUNTIME_FILE" && -f "$PROFILE_FILE" ]] || fail 'runtime/profile/secret file missing'
[[ -f "$CLIENT_INFO_FILE" ]] || fail 'client-info file not found'
[[ -f "$CONFIG_FILE" ]] || fail 'live sing-box config not found'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required'

set -a
source "$RUNTIME_FILE"
source "$PROFILE_FILE"
source "$MULTI_RUNTIME_FILE"
source "$CLIENT_INFO_FILE"
set +a

pick_user(){
  local candidate selected
  if [[ -n "$CLIENT_USER" ]]; then
    id "$CLIENT_USER" >/dev/null 2>&1 || fail "unknown client user: $CLIENT_USER"
    return
  fi
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]] && getent passwd "$SUDO_USER" >/dev/null; then
    candidate=$SUDO_USER
  elif getent passwd juya >/dev/null; then
    candidate=juya
  else
    candidate=$(getent passwd | awk -F: '$3>=1000 && $6 ~ /^\/home\// {print $1; exit}')
  fi
  [[ -n "${candidate:-}" ]] || fail 'could not determine a normal home user; set CLIENT_USER=<user>'
  if [[ -t 0 ]]; then
    printf 'Client bundle user [%s]: ' "$candidate" >&2
    read -r selected || true
    [[ -n "${selected:-}" ]] && candidate=$selected
  fi
  id "$candidate" >/dev/null 2>&1 || fail "unknown client user: $candidate"
  CLIENT_USER=$candidate
}

pick_user
USER_HOME=$(getent passwd "$CLIENT_USER" | cut -d: -f6)
[[ -d "$USER_HOME" ]] || fail "home directory missing: $USER_HOME"
OUT_DIR="$USER_HOME/vpn-client"
TMP_DIR=$(mktemp -d /tmp/joohar-client-bundle.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT
chmod 0700 "$TMP_DIR"

SERVER_IP=${PUBLIC_IPV4:-${SNIPROXY_PUBLIC_IPV4:-}}
if [[ -z "$SERVER_IP" ]]; then SERVER_IP=$(curl -4 -fsS https://api.ipify.org || true); fi
[[ -n "$SERVER_IP" ]] || fail 'could not determine public IPv4'

python3 - "$CONFIG_FILE" "$TMP_DIR" "$SERVER_IP" <<'PY'
import base64, json, os, sys, urllib.parse
from pathlib import Path

config_path, out_dir, server_ip = sys.argv[1:]
out=Path(out_dir)
config=json.loads(Path(config_path).read_text())
by_tag={x.get('tag'):x for x in config.get('inbounds',[])}

def user(inbound): return ((inbound or {}).get('users') or [{}])[0]
def write(name, text):
    p=out/name; p.write_text(text.rstrip()+"\n"); p.chmod(0o600); return text.strip()
def q(v): return urllib.parse.quote(str(v), safe='')
def write_vmess(name, add, port, uuid, host, path, sni):
    payload={"v":"2","ps":name,"add":add,"port":str(port),"id":uuid,"aid":"0","scy":"auto","net":"ws","type":"none","host":host,"path":path,"tls":"tls","sni":sni}
    raw=base64.b64encode(json.dumps(payload,separators=(',',':')).encode()).decode()
    return write('vmess-ws.txt','vmess://'+raw)

links=[]; env=os.environ; host_cf=env.get('PUBLIC_HOSTNAME','echo.engine.qzz.io'); uuid=env.get('VLESS_UUID',''); reality_sni=env.get('REALITY_SERVER_NAME','www.cloudflare.com'); reality_sid=env.get('REALITY_SHORT_ID',''); public_key=env.get('REALITY_PUBLIC_KEY',''); flow='xtls-rprx-vision'

v=by_tag.get('vless-reality')
if v and uuid and public_key:
    links.append(write('vless-reality.txt',f"vless://{q(uuid)}@{server_ip}:{v.get('listen_port',8443)}?encryption=none&flow={q(flow)}&security=reality&pbk={q(public_key)}&fp=chrome&sni={q(reality_sni)}&sid={q(reality_sid)}&type=tcp#Echo-VLESS-Reality").strip())
ws=by_tag.get('vless-ws')
if ws:
    path=ws.get('transport',{}).get('path','/vless-ws')
    links.append(write('vless-ws.txt',f"vless://{q(uuid)}@{host_cf}:443?encryption=none&security=tls&sni={q(host_cf)}&type=ws&host={q(host_cf)}&path={q(path)}#Echo-VLESS-WS").strip())
hu=by_tag.get('vless-httpupgrade')
if hu:
    path=hu.get('transport',{}).get('path','/vless-hu')
    links.append(write('vless-httpupgrade.txt',f"vless://{q(uuid)}@{host_cf}:443?encryption=none&security=tls&sni={q(host_cf)}&type=httpupgrade&host={q(host_cf)}&path={q(path)}#Echo-VLESS-HTTPUpgrade").strip())
vm=by_tag.get('vmess-ws')
if vm:
    path=vm.get('transport',{}).get('path','/vmess-ws')
    links.append(write_vmess('Echo-VMess-WS',host_cf,443,uuid,host_cf,path,host_cf).strip())
ss=by_tag.get('shadowsocks')
if ss:
    method=ss.get('method','chacha20-ietf-poly1305'); encoded=base64.urlsafe_b64encode(f"{method}:{ss.get('password','')}".encode()).decode().rstrip('=')
    links.append(write('shadowsocks.txt',f"ss://{encoded}@{server_ip}:{ss.get('listen_port',8444)}#Echo-SS").strip())
ss2=by_tag.get('shadowsocks-2022')
if ss2:
    method=ss2.get('method','2022-blake3-chacha20-poly1305'); encoded=base64.urlsafe_b64encode(f"{method}:{ss2.get('password','')}".encode()).decode().rstrip('=')
    links.append(write('shadowsocks-2022.txt',f"ss://{encoded}@{server_ip}:{ss2.get('listen_port',8445)}#Echo-SS-2022").strip())
socks=by_tag.get('socks5')
if socks:
    u=user(socks); links.append(write('socks5.txt',f"socks://{q(u.get('username',''))}:{q(u.get('password',''))}@{server_ip}:{socks.get('listen_port',1080)}#Echo-SOCKS5").strip())
http=by_tag.get('http-proxy')
if http:
    u=user(http); write('http-proxy.txt',f"http://{q(u.get('username',''))}:{q(u.get('password',''))}@{server_ip}:{http.get('listen_port',8080)}#Echo-HTTP-Proxy")

if env.get('ENABLE_DIRECT_TLS','0') == '1':
    tls_sni=env.get('TLS_SERVER_NAME',host_cf)
    t=by_tag.get('trojan')
    if t: links.append(write('trojan.txt',f"trojan://{q(user(t).get('password',''))}@{server_ip}:{t.get('listen_port',8448)}?security=tls&sni={q(tls_sni)}#Echo-Trojan").strip())
    h=by_tag.get('hysteria2')
    if h: links.append(write('hysteria2.txt',f"hysteria2://{q(user(h).get('password',''))}@{server_ip}:{h.get('listen_port',8446)}/?sni={q(tls_sni)}#Echo-Hysteria2").strip())
    tu=by_tag.get('tuic')
    if tu:
        u=user(tu); links.append(write('tuic.txt',f"tuic://{q(u.get('uuid',''))}:{q(u.get('password',''))}@{server_ip}:{tu.get('listen_port',8447)}/?sni={q(tls_sni)}&congestion_control=bbr#Echo-TUIC").strip())
    at=by_tag.get('anytls')
    if at: links.append(write('anytls.txt',f"anytls://{q(user(at).get('password',''))}@{server_ip}:{at.get('listen_port',8449)}/?security=tls&type=tcp&sni={q(tls_sni)}#Echo-AnyTLS").strip())
    gr=by_tag.get('vless-grpc')
    if gr:
        service=gr.get('transport',{}).get('service_name','EchoService')
        links.append(write('vless-grpc.txt',f"vless://{q(uuid)}@{server_ip}:{gr.get('listen_port',8450)}?encryption=none&security=tls&sni={q(tls_sni)}&alpn=h2&type=grpc&serviceName={q(service)}#Echo-VLESS-gRPC").strip())

v2ray_links=[x for x in links if not x.startswith('http://')]
write('v2rayn-import.txt','\n'.join(v2ray_links))
write('all-import-links.txt','\n'.join(links))
write('v2rayn-import-base64.txt',base64.b64encode(('\n'.join(v2ray_links)+'\n').encode()).decode())
summary=['Joohar / Echo client bundle','','Server IPv4: '+server_ip,'Cloudflare hostname: '+host_cf,'','Files:']+[p.name for p in sorted(out.iterdir()) if p.is_file()]
write('README.txt','\n'.join(summary))
write('summary.txt','\n'.join(summary))
PY

install -d -m 0700 "$USER_HOME"
rm -rf "$OUT_DIR.new"
cp -a "$TMP_DIR" "$OUT_DIR.new"
chown -R "$CLIENT_USER":"$(id -gn "$CLIENT_USER")" "$OUT_DIR.new"
chmod 0700 "$OUT_DIR.new"
rm -rf "$OUT_DIR"
mv "$OUT_DIR.new" "$OUT_DIR"
printf 'client-bundle: generated under %s for user %s\n' "$OUT_DIR" "$CLIENT_USER"
printf 'client-bundle: v2rayN import links are in %s/v2rayn-import.txt\n' "$OUT_DIR"
