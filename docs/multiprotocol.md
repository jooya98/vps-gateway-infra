# Echo multi-protocol gateway

This layer is intentionally additive. Pulling the repository does **not** change a live VPS. Do not rerun `bootstrap.sh` or `deploy/deploy.sh` merely to test this feature.

## Design

The existing Echo listeners are preserved by `scripts/activate-multiprotocol.sh`:

- VLESS + Reality + Vision: the currently deployed listen address/port and credentials are detected from the live config/runtime.
- Legacy Shadowsocks: the currently deployed listen address/port and password are preserved.
- SOCKS5: the currently deployed listen address/port and credentials are preserved.

Additional listeners:

| Protocol | Origin/listen | Default | Exposure |
|---|---|---:|---|
| VLESS + WebSocket | `127.0.0.1:18080` | enabled | Cloudflare Tunnel |
| VMess + WebSocket | `127.0.0.1:18081` | enabled | Cloudflare Tunnel |
| VLESS + HTTPUpgrade | `127.0.0.1:18082` | enabled | Cloudflare Tunnel / compatibility |
| Shadowsocks 2022 | `:::8445` | enabled | direct TCP/UDP |
| Hysteria2 | `:::8446` | optional | direct UDP + TLS |
| TUIC | `:::8447` | optional | direct UDP + TLS |
| Trojan | `:::8448` | optional | direct TCP + TLS |
| AnyTLS | `:::8449` | optional | direct TCP + TLS |
| VLESS + gRPC | `:::8450` | optional | direct TCP + TLS |

The optional TLS/QUIC family is disabled until a real certificate/key pair is available. Set `ENABLE_DIRECT_TLS=1`, `TLS_CERT_PATH`, and `TLS_KEY_PATH` before activation when those endpoints are ready.

## Cloudflare Tunnel

For `echo.engine.qzz.io`, keep the existing token-based `cloudflared` service. Add published application routes in the Cloudflare Tunnel dashboard:

- `echo.engine.qzz.io` + path `/vless-ws` -> `http://127.0.0.1:18080`
- `echo.engine.qzz.io` + path `/vmess-ws` -> `http://127.0.0.1:18081`
- `echo.engine.qzz.io` + path `/vless-hu` -> `http://127.0.0.1:18082`

The public side is HTTPS on 443; the origin services stay loopback-only. Cloudflare Tunnel supports WebSockets. Public-hostname gRPC is currently not supported by Cloudflare Tunnel, so the gRPC listener remains a direct TLS endpoint rather than being put behind the Tunnel.

Do **not** move the Reality listener behind the Tunnel: Reality expects its own TLS handshake and is not equivalent to an HTTP/WebSocket origin behind Cloudflare termination.

## Safe activation on an existing VPS

First validate without changing the live service:

```bash
cd /opt/vps-gateway-infra
git pull --ff-only
sudo DRY_RUN=1 bash scripts/activate-multiprotocol.sh
```

If validation succeeds, activate:

```bash
sudo bash scripts/activate-multiprotocol.sh
```

The script:

1. Reads the existing runtime credentials.
2. Detects the live Reality/Shadowsocks/SOCKS listeners from the current config.
3. Generates new protocol credentials only once in `/root/vps-gateway-multiprotocol.conf`.
4. Validates the complete generated config with `sing-box check`.
5. Backs up `/etc/sing-box/config.json`.
6. Atomically installs the new config and restarts only `sing-box.service`.
7. Automatically restores the previous config if the new service fails to start.

It does **not** install packages, alter SSH hardening, modify UFW, modify the Cloudflare token, or run the full bootstrap/deploy workflow.

## Firewall

The activation script deliberately does not modify firewall policy. This avoids turning a pull/test into a network-policy mutation. The Cloudflare-backed WebSocket endpoints require no new public origin port. Before enabling the direct TLS/QUIC family, explicitly add the required TCP/UDP ports to the firewall policy and verify them independently.
