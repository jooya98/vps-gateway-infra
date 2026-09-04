#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${ENV_FILE:-"$ROOT/.env"}; OUT_DIR=${OUT_DIR:-"$ROOT/.generated"}
set -a; source "$ROOT/config/defaults.env.example"; PROFILE=${PROFILE:-default}; PROFILE_FILE="$ROOT/config/profiles/$PROFILE.env.example"; [[ -f "$PROFILE_FILE" ]] || { printf 'render: profile not found: %s\n' "$PROFILE" >&2; exit 1; }; source "$PROFILE_FILE"; [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"; set +a
required=(VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID SOCKS_USERNAME SOCKS_PASSWORD VLESS_PORT SOCKS_LISTEN_ADDRESS SOCKS_LISTEN_PORT REALITY_SERVER_NAME REALITY_HANDSHAKE_SERVER REALITY_HANDSHAKE_PORT SING_BOX_LOG_LEVEL); missing=(); for name in "${required[@]}"; do [[ -n "${!name:-}" ]] || missing+=("$name"); done
if [[ "$ENABLE_SHADOWSOCKS" == true || "$ENABLE_VMESS" == true || "$ENABLE_TROJAN" == true || "$ENABLE_HYSTERIA2" == true || "$ENABLE_TUIC" == true ]]; then [[ -n "${TRANSPORT_PASSWORD:-}" ]] || missing+=(TRANSPORT_PASSWORD); fi
if [[ "$ENABLE_VMESS" == true || "$ENABLE_TROJAN" == true || "$ENABLE_HYSTERIA2" == true || "$ENABLE_TUIC" == true ]]; then [[ -n "${TLS_SERVER_NAME:-}" ]] || missing+=(TLS_SERVER_NAME); [[ -n "${TLS_CERT_PATH:-}" ]] || missing+=(TLS_CERT_PATH); [[ -n "${TLS_KEY_PATH:-}" ]] || missing+=(TLS_KEY_PATH); fi
if [[ "$ENABLE_DNS_STEERING" == true ]]; then [[ -n "${SNIPROXY_PUBLIC_IPV4:-}" ]] || missing+=(SNIPROXY_PUBLIC_IPV4); fi
if [[ "$ENABLE_CLOUDFLARED" == true ]]; then [[ -n "${CLOUDFLARED_TUNNEL_TOKEN:-}" ]] || missing+=(CLOUDFLARED_TUNNEL_TOKEN); fi
if ((${#missing[@]})); then printf 'render: missing required variables (%s)\n' "${missing[*]}" >&2; exit 1; fi
rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR/sing-box" "$OUT_DIR/ssh" "$OUT_DIR/cloudflared" "$OUT_DIR/sniproxy"
python3 - "$ROOT" "$OUT_DIR" <<'PY'
import json, os, re, sys
from pathlib import Path
root,out=map(Path,sys.argv[1:]); env=os.environ; truth=lambda k: env.get(k,"false").lower()=="true"; inbounds=[]
if truth("ENABLE_VLESS"): inbounds.append({"type":"vless","tag":"vless-in","listen":"::","listen_port":int(env["VLESS_PORT"]),"users":[{"name":"personal","uuid":env["VLESS_UUID"],"flow":"xtls-rprx-vision"}],"tls":{"enabled":True,"server_name":env["REALITY_SERVER_NAME"],"reality":{"enabled":True,"handshake":{"server":env["REALITY_HANDSHAKE_SERVER"],"server_port":int(env["REALITY_HANDSHAKE_PORT"])},"private_key":env["REALITY_PRIVATE_KEY"],"short_id":[env["REALITY_SHORT_ID"]]}}})
if truth("ENABLE_SHADOWSOCKS"): inbounds.append({"type":"shadowsocks","tag":"shadowsocks-in","listen":"::","listen_port":int(env["SHADOWSOCKS_PORT"]),"method":env.get("SHADOWSOCKS_METHOD","chacha20-ietf-poly1305"),"password":env["TRANSPORT_PASSWORD"]})
def tls(): return {"enabled":True,"server_name":env["TLS_SERVER_NAME"],"certificate_path":env["TLS_CERT_PATH"],"key_path":env["TLS_KEY_PATH"]}
if truth("ENABLE_VMESS"): inbounds.append({"type":"vmess","tag":"vmess-in","listen":"::","listen_port":int(env["VMESS_PORT"]),"users":[{"name":"personal","uuid":env["VLESS_UUID"],"alterId":0}],"tls":tls()})
if truth("ENABLE_TROJAN"): inbounds.append({"type":"trojan","tag":"trojan-in","listen":"::","listen_port":int(env["TROJAN_PORT"]),"users":[{"name":"personal","password":env["TRANSPORT_PASSWORD"]}],"tls":tls()})
if truth("ENABLE_HYSTERIA2"): inbounds.append({"type":"hysteria2","tag":"hysteria2-in","listen":"::","listen_port":int(env["HYSTERIA2_PORT"]),"users":[{"name":"personal","password":env["TRANSPORT_PASSWORD"]}],"tls":tls(),"up_mbps":int(env.get("HYSTERIA2_UP_MBPS","100")),"down_mbps":int(env.get("HYSTERIA2_DOWN_MBPS","100"))})
if truth("ENABLE_TUIC"): inbounds.append({"type":"tuic","tag":"tuic-in","listen":"::","listen_port":int(env["TUIC_PORT"]),"users":[{"name":"personal","uuid":env["VLESS_UUID"],"password":env["TRANSPORT_PASSWORD"]}],"tls":tls(),"congestion_control":"cubic","zero_rtt_handshake":False})
if truth("ENABLE_SOCKS"): inbounds.append({"type":"socks","tag":"socks-in","listen":env["SOCKS_LISTEN_ADDRESS"],"listen_port":int(env["SOCKS_LISTEN_PORT"]),"users":[{"username":env["SOCKS_USERNAME"],"password":env["SOCKS_PASSWORD"]}]})
if not inbounds: raise SystemExit("render: no sing-box inbound is enabled")
template=(root/"templates/sing-box/config.json.tmpl").read_text().replace("${SING_BOX_INBOUNDS_JSON}",json.dumps(inbounds,indent=2)).replace("${SING_BOX_LOG_LEVEL}",env["SING_BOX_LOG_LEVEL"])
if re.search(r"\$\{[A-Z][A-Z0-9_]*\}",template): raise SystemExit("render: unresolved template variable")
json.loads(template); (out/"sing-box/config.json").write_text(template+"\n")
for src,dst in [("templates/sing-box/sing-box.service.tmpl","sing-box/sing-box.service"),("templates/ssh/00-vps-gateway-hardening.conf.tmpl","ssh/00-vps-gateway-hardening.conf")]:
 text=(root/src).read_text(); text=re.sub(r"\$\{([A-Z][A-Z0-9_]*)\}",lambda m:env.get(m.group(1),m.group(0)),text); (out/dst).write_text(text)
if truth("ENABLE_CLOUDFLARED"):
 text=(root/"templates/cloudflared/cloudflared.service.tmpl").read_text(); text=re.sub(r"\$\{([A-Z][A-Z0-9_]*)\}",lambda m:env.get(m.group(1),m.group(0)),text); (out/"cloudflared/cloudflared.service").write_text(text)
if truth("ENABLE_DNS_STEERING"):
 domain_src=root/"config/gateway/domains/ai-domains.txt"; domains=[x.strip().rstrip('.') for x in domain_src.read_text().splitlines() if x.strip() and not x.lstrip().startswith('#')]
 if not domains: raise SystemExit("render: DNS domain inventory is empty")
 (out/"sniproxy/domains.csv").write_text("".join(f"{d}.,suffix\n" for d in domains)); cidrs=[x.strip() for x in env.get("DNS_ALLOWED_CIDRS","").split(';') if x.strip()]
 if not cidrs: raise SystemExit("render: DNS_ALLOWED_CIDRS is empty")
 (out/"sniproxy/cidr.csv").write_text("\n".join(cidrs)+"\n0.0.0.0/0,reject\n::/0,reject\n")
 yaml=f'''general:
  upstream_dns: {env["SNIPROXY_UPSTREAM_DNS"]}
  bind_dns_over_udp: "{env["SNIPROXY_BIND_ADDRESS"]}:{env["SNIPROXY_DNS_PORT"]}"
  bind_dns_over_tcp: "{env["SNIPROXY_BIND_ADDRESS"]}:{env["SNIPROXY_DNS_PORT"]}"
  bind_http:
  bind_https: "{env["SNIPROXY_BIND_ADDRESS"]}:{env["SNIPROXY_HTTPS_PORT"]}"
  public_ipv4: "{env["SNIPROXY_PUBLIC_IPV4"]}"
  allow_conn_to_local: false
  log_level: {env["SNIPROXY_LOG_LEVEL"]}
acl:
  domain:
    enabled: true
    priority: 20
    path: "{env["SNIPROXY_DOMAINS_PATH"]}"
    refresh_interval: 1h0m0s
  cidr:
    enabled: true
    priority: 30
    path: "{env["SNIPROXY_CIDR_PATH"]}"
    refresh_interval: 1h0m0s
  geoip:
    enabled: false
  override:
    enabled: false
'''
 (out/"sniproxy/config.yaml").write_text(yaml)
PY
chmod 0600 "$OUT_DIR/sing-box/config.json"; chmod 0644 "$OUT_DIR"/sing-box/sing-box.service "$OUT_DIR"/ssh/00-vps-gateway-hardening.conf
if [[ -f "$OUT_DIR/cloudflared/cloudflared.service" ]]; then chmod 0644 "$OUT_DIR/cloudflared/cloudflared.service"; fi
if compgen -G "$OUT_DIR/sniproxy/*" >/dev/null 2>&1; then chmod 0644 "$OUT_DIR"/sniproxy/*; fi
printf 'render: generated profile=%s under %s\n' "$PROFILE" "$OUT_DIR"
