# Echo multi-protocol gateway

This layer is intentionally additive. Pulling the repository does **not** change a live VPS. Do not rerun `bootstrap.sh` or `deploy/deploy.sh` merely to test this feature.

## Listener model

Direct transports bind explicitly to IPv4 `0.0.0.0`. This includes SOCKS5 and HTTP proxy; both use the existing gateway credentials. `0.0.0.0` is the deterministic public IPv4 bind, while the Cloudflare-backed application transports remain loopback-only.

| Protocol | Origin/listen | Exposure |
|---|---|---|
| VLESS + Reality + Vision | `0.0.0.0:8443` | direct IPv4 |
| Shadowsocks | `0.0.0.0:8444` | direct IPv4 |
| Shadowsocks 2022 | `0.0.0.0:8445` | direct IPv4 |
| SOCKS5 | `0.0.0.0:1080` | direct IPv4, authenticated |
| HTTP proxy | `0.0.0.0:8080` | direct IPv4, authenticated |
| VLESS + WebSocket | `127.0.0.1:18080` | Cloudflare Tunnel |
| VMess + WebSocket | `127.0.0.1:18081` | Cloudflare Tunnel |
| VLESS + HTTPUpgrade | `127.0.0.1:18082` | Cloudflare Tunnel |
| Hysteria2 | `0.0.0.0:8446` | direct UDP + TLS when enabled |
| TUIC | `0.0.0.0:8447` | direct UDP + TLS when enabled |
| Trojan | `0.0.0.0:8448` | direct TCP + TLS when enabled |
| AnyTLS | `0.0.0.0:8449` | direct TCP + TLS when enabled |
| VLESS + gRPC | `0.0.0.0:8450` | direct TCP + TLS when enabled |

The optional TLS/QUIC family remains disabled until a trusted certificate/key pair is available. Set `ENABLE_DIRECT_TLS=1` with valid `TLS_CERT_PATH` and `TLS_KEY_PATH` before activation.

## Cloudflare Tunnel

The multiprotocol path uses a **locally-managed** Cloudflare Tunnel. `scripts/activate-cloudflared-local.sh` takes a scoped Cloudflare API token and account ID, creates a local-config tunnel if needed, writes a tunnel-scoped credential file, renders `config.yml`, creates the DNS CNAME, and installs the dedicated systemd unit.

Required provisioning values:

```text
CLOUDFLARE_API_TOKEN=...
CLOUDFLARE_ACCOUNT_ID=...
```

The API token is provisioning material only. The long-running connector authenticates with the tunnel-specific credential file. Cloudflare documents locally-managed tunnels as using a local YAML configuration and tunnel credential file; remotely-managed tunnels instead use a run token and dashboard/API configuration. citeturn140830search0turn363662search1

Ingress:

- `echo.engine.qzz.io` + `/vless-ws` -> `http://127.0.0.1:18080`
- `echo.engine.qzz.io` + `/vmess-ws` -> `http://127.0.0.1:18081`
- `echo.engine.qzz.io` + `/vless-hu` -> `http://127.0.0.1:18082`
- catch-all -> HTTP 404

The config deliberately keeps the three HTTP-origin transports loopback-only. Cloudflare requires a catch-all rule at the end of a local ingress configuration. citeturn140830search0

## Safe activation on an existing VPS

First validate the sing-box layer without changing live state:

```bash
cd /opt/vps-gateway-infra
git pull --ff-only
sudo DRY_RUN=1 bash scripts/activate-multiprotocol.sh
```

Then validate the Cloudflare local configuration. This dry-run does not create a tunnel or DNS record:

```bash
sudo DRY_RUN=1 bash scripts/activate-cloudflared-local.sh
```

Only after both validations succeed should the live layers be activated.

## Client bundle

Generate the complete bundle from the **live** sing-box config:

```bash
sudo bash scripts/generate-multiprotocol-clients.sh
```

The script detects a normal home user and asks for the destination user when interactive. Use `CLIENT_USER=<user>` for automation. Output is stored as:

```text
/home/<user>/vpn-client/
```

Each enabled protocol has its own `.txt` share-link file. Additionally:

- `all-import-links.txt` contains every generated import URI, including HTTP proxy.
- `v2rayn-import.txt` contains standard share URIs for the protocols supported by current v2rayN import flows.
- `v2rayn-import-base64.txt` contains the same v2rayN entries as one base64 blob for clipboard/subscription-style import.

Current v2rayN documentation lists VMess, Shadowsocks, SOCKS, VLESS, Trojan, Hysteria2, TUIC, WireGuard and AnyTLS among supported subscription/share protocols. citeturn886821search2

The generator reads the live configuration, so ports and server credentials are not duplicated in a second source of truth. It never writes the server's Reality private key or Cloudflare tunnel credentials into the client bundle.

## Firewall

The sing-box activation script deliberately does not modify UFW. Cloudflare-backed WS/HTTPUpgrade origins require no new public origin ports. Public SOCKS/HTTP, Shadowsocks and Reality require their corresponding IPv4 firewall rules. Direct TLS/QUIC ports require explicit TCP/UDP firewall rules before they can be used.
