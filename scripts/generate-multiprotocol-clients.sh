#!/usr/bin/env bash
set -euo pipefail
fail(){ printf 'client-bundle: %s\n' "$1" >&2; exit 1; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_FILE=${RUNTIME_FILE:-/root/vps-gateway-runtime.conf}
MULTI_RUNTIME_FILE=${MULTI_RUNTIME_FILE:-/root/vps-gateway-multiprotocol.conf}
CONFIG_FILE=${CONFIG_FILE:-/etc/sing-box/config.json}
CLIENT_INFO_FILE=${CLIENT_INFO_FILE:-/root/vps-gateway-client-info.txt}
PROFILE_FILE=${PROFILE_FILE:-"$ROOT/config/profiles/gateway.env.example"}
CLIENT_USER=${CLIENT_USER:-}
[[ $EUID -eq 0 ]] || fail 'run as root so the live config and secret stores can be read'
[[ -f "$RUNTIME_FILE" && -f "$MULTI_RUNTIME_FILE" && -f "$PROFILE_FILE" && -f "$CLIENT_INFO_FILE" && -f "$CONFIG_FILE" ]] || fail 'runtime/profile/secret/config file missing'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
set -a; source "$RUNTIME_FILE"; source "$PROFILE_FILE"; source "$MULTI_RUNTIME_FILE"; source "$CLIENT_INFO_FILE"; set +a
pick_user(){
 local candidate selected
 if [[ -n "$CLIENT_USER" ]]; then id "$CLIENT_USER" >/dev/null 2>&1 || fail "unknown client user: $CLIENT_USER"; return; fi
 if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]] && getent passwd "$SUDO_USER" >/dev/null; then candidate=$SUDO_USER
 elif getent passwd juya >/dev/null; then candidate=juya
 else candidate=$(getent passwd | awk -F: '$3>=1000 && $6 ~ /^\/home\// {print $1; exit}'); fi
 [[ -n "${candidate:-}" ]] || fail 'could not determine a normal home user'
 if [[ -t 0 ]]; then printf 'Client bundle user [%s]: ' "$candidate" >&2; read -r selected || true; [[ -n "${selected:-}" ]] && candidate=$selected; fi
 id "$candidate" >/dev/null 2>&1 || fail "unknown client user: $candidate"; CLIENT_USER=$candidate
}
pick_user
USER_HOME=$(getent passwd "$CLIENT_USER" | cut -d: -f6); [[ -d "$USER_HOME" ]] || fail "home directory missing: $USER_HOME"
OUT_DIR="$USER_HOME/vpn-client"; TMP_DIR=$(mktemp -d /tmp/joohar-client-bundle.XXXXXX); trap 'rm -rf "$TMP_DIR"' EXIT; chmod 0700 "$TMP_DIR"
SERVER_IP=${PUBLIC_IPV4:-}; [[ -n "$SERVER_IP" ]] || SERVER_IP=$(curl -4 -fsS https://api.ipify.org || true); [[ -n "$SERVER_IP" ]] || fail 'could not determine public IPv4'
python3 - "$CONFIG_FILE" "$TMP_DIR" "$SERVER_IP" "$PUBLIC_HOSTNAME" "$DIRECT_HOSTNAME" <<'PY'
import base64,json,os,sys,urllib.parse
from pathlib import Path
config_path,out_dir,server_ip,host_cf,direct_host=sys.argv[1:]
out=Path(out_dir); config=json.loads(Path(config_path).read_text()); by_tag={x.get('tag'):x for x in config.get('inbounds',[])}
def user(x): return ((x or {}).get('users') or [{}])[0]
def write(name,text): p=out/name; p.write_text(text.rstrip()+'\n'); p.chmod(0o600); return text.strip()
def q(v): return urllib.parse.quote(str(v),safe='')
def vmess(add,port,uuid,host,path,sni):
 payload={"v":"2","ps":"Echo-VMess-WS","add":add,"port":str(port),"id":uuid,"aid":"0","scy":"auto","net":"ws","type":"none","host":host,"path":path,"tls":"tls","sni":sni}
 return 'vmess://'+base64.b64encode(json.dumps(payload,separators=(',',':')).encode()).decode()
links=[]; uuid=os.environ.get('VLESS_UUID',''); reality_sni=os.environ.get('REALITY_SERVER_NAME','www.cloudflare.com'); sid=os.environ.get('REALITY_SHORT_ID',''); pub=os.environ.get('REALITY_PUBLIC_KEY','');
v=by_tag.get('vless-reality')
if v and uuid and pub: links.append(write('vless-reality.txt',f"vless://{q(uuid)}@{server_ip}:{v.get('listen_port',8443)}?encryption=none&flow=xtls-rprx-vision&security=reality&pbk={q(pub)}&fp=chrome&sni={q(reality_sni)}&sid={q(sid)}&type=tcp#Echo-VLESS-Reality"))
ws=by_tag.get('vless-ws')
if ws: links.append(write('vless-ws.txt',f"vless://{q(uuid)}@{host_cf}:443?encryption=none&security=tls&sni={q(host_cf)}&type=ws&host={q(host_cf)}&path={q(ws.get('transport',{}).get('path','/vless-ws'))}#Echo-VLESS-WS"))
hu=by_tag.get('vless-httpupgrade')
if hu: links.append(write('vless-httpupgrade.txt',f"vless://{q(uuid)}@{host_cf}:443?encryption=none&security=tls&sni={q(host_cf)}&type=httpupgrade&host={q(host_cf)}&path={q(hu.get('transport',{}).get('path','/vless-hu'))}#Echo-VLESS-HTTPUpgrade"))
vm=by_tag.get('vmess-ws')
if vm: links.append(write('vmess-ws.txt',vmess(host_cf,443,uuid,host_cf,vm.get('transport',{}).get('path','/vmess-ws'),host_cf)))
ss=by_tag.get('shadowsocks')
if ss:
 enc=base64.urlsafe_b64encode(f"{ss.get('method','chacha20-ietf-poly1305')}:{ss.get('password','')}".encode()).decode().rstrip('='); links.append(write('shadowsocks.txt',f"ss://{enc}@{server_ip}:{ss.get('listen_port',8444)}#Echo-SS"))
ss2=by_tag.get('shadowsocks-2022')
if ss2:
 enc=base64.urlsafe_b64encode(f"{ss2.get('method','2022-blake3-chacha20-poly1305')}:{ss2.get('password','')}".encode()).decode().rstrip('='); links.append(write('shadowsocks-2022.txt',f"ss://{enc}@{server_ip}:{ss2.get('listen_port',8445)}#Echo-SS-2022"))
socks=by_tag.get('socks5')
if socks: links.append(write('socks5.txt',f"socks://{q(user(socks).get('username',''))}:{q(user(socks).get('password',''))}@{server_ip}:{socks.get('listen_port',1080)}#Echo-SOCKS5"))
http=by_tag.get('http-proxy')
if http: write('http-proxy.txt',f"http://{q(user(http).get('username',''))}:{q(user(http).get('password',''))}@{server_ip}:{http.get('listen_port',8080)}#Echo-HTTP-Proxy")
if os.environ.get('ENABLE_DIRECT_TLS','0')=='1':
 tls=os.environ.get('TLS_SERVER_NAME',direct_host)
 t=by_tag.get('trojan'); h=by_tag.get('hysteria2'); tu=by_tag.get('tuic'); at=by_tag.get('anytls'); gr=by_tag.get('vless-grpc')
 if t: links.append(write('trojan.txt',f"trojan://{q(user(t).get('password',''))}@{server_ip}:{t.get('listen_port',8448)}?security=tls&sni={q(tls)}#Echo-Trojan"))
 if h: links.append(write('hysteria2.txt',f"hysteria2://{q(user(h).get('password',''))}@{server_ip}:{h.get('listen_port',8446)}/?sni={q(tls)}#Echo-Hysteria2"))
 if tu: links.append(write('tuic.txt',f"tuic://{q(user(tu).get('uuid',''))}:{q(user(tu).get('password',''))}@{server_ip}:{tu.get('listen_port',8447)}/?sni={q(tls)}&congestion_control=bbr#Echo-TUIC"))
 if at: links.append(write('anytls.txt',f"anytls://{q(user(at).get('password',''))}@{server_ip}:{at.get('listen_port',8449)}/?security=tls&type=tcp&sni={q(tls)}#Echo-AnyTLS"))
 if gr: links.append(write('vless-grpc.txt',f"vless://{q(uuid)}@{server_ip}:{gr.get('listen_port',8450)}?encryption=none&security=tls&sni={q(tls)}&alpn=h2&type=grpc&serviceName={q(gr.get('transport',{}).get('service_name','EchoService'))}#Echo-VLESS-gRPC"))
v2=[x for x in links if not x.startswith('http://')]
write('v2rayn-import.txt','\n'.join(v2)); write('all-import-links.txt','\n'.join(links)); write('v2rayn-import-base64.txt',base64.b64encode(('\n'.join(v2)+'\n').encode()).decode())
summary=['Joohar / Echo client bundle','','Server IPv4: '+server_ip,'Tunnel hostname: '+host_cf,'Direct hostname: '+direct_host,'','Files:']+[p.name for p in sorted(out.iterdir()) if p.is_file()]
write('README.txt','\n'.join(summary)); write('summary.txt','\n'.join(summary))
PY
install -d -m 0700 "$USER_HOME"; rm -rf "$OUT_DIR.new"; cp -a "$TMP_DIR" "$OUT_DIR.new"; chown -R "$CLIENT_USER":"$(id -gn "$CLIENT_USER")" "$OUT_DIR.new"; chmod 0700 "$OUT_DIR.new"; rm -rf "$OUT_DIR"; mv "$OUT_DIR.new" "$OUT_DIR"
printf 'client-bundle: generated under %s\n' "$OUT_DIR"
