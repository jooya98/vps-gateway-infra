# Echo comprehensive gateway

The repository has one production profile and one public installation entrypoint:

```bash
sudo bash bootstrap.sh
```

There are no separate activation commands. Bootstrap collects host-specific values, preserves existing state, and invokes the helper scripts internally.

## Listener model

| Protocol | Listen | Exposure |
|---|---|---|
| VLESS + Reality + Vision | `0.0.0.0:8443` | direct IPv4 |
| Shadowsocks | `0.0.0.0:8444` | direct IPv4 |
| Shadowsocks 2022 | `0.0.0.0:8445` | direct IPv4 |
| Hysteria2 | `0.0.0.0:8446` | direct UDP + TLS |
| TUIC | `0.0.0.0:8447` | direct UDP + TLS |
| Trojan | `0.0.0.0:8448` | direct TCP + TLS |
| AnyTLS | `0.0.0.0:8449` | direct TCP + TLS |
| VLESS + gRPC | `0.0.0.0:8450` | direct TCP + TLS |
| SOCKS5 | `0.0.0.0:1080` | direct IPv4, authenticated |
| HTTP proxy | `0.0.0.0:8080` | direct IPv4, authenticated |
| VLESS + WebSocket | `127.0.0.1:18080` | Cloudflare Tunnel |
| VMess + WebSocket | `127.0.0.1:18081` | Cloudflare Tunnel |
| VLESS + HTTPUpgrade | `127.0.0.1:18082` | Cloudflare Tunnel |

## Cloudflare

The installation uses a locally-managed Cloudflare Tunnel. The interactive bootstrap collects the API token, account ID, zone, public hostname, direct hostname, and tunnel name, then stores the resulting runtime inputs in the root-only runtime file.

The public hostname is proxied through Cloudflare:

```text
echo.engine.qzz.io
  /vless-ws  -> 127.0.0.1:18080
  /vmess-ws  -> 127.0.0.1:18081
  /vless-hu  -> 127.0.0.1:18082
```

The direct hostname is deliberately DNS-only:

```text
direct.echo.engine.qzz.io -> Echo public IPv4
```

That separation is required because the raw TCP/UDP transports are not served through the HTTP Tunnel ingress path.

## TLS

Bootstrap creates the direct hostname DNS record before requesting a trusted Let's Encrypt certificate through Cloudflare DNS-01. The certificate covers both public hostnames and is copied to the paths consumed by sing-box.

Certbot keeps the Cloudflare credential file root-only and reuses it for renewal. The Certbot Cloudflare plugin supports restricted API tokens and requires DNS editing access for the managed zone. citeturn320645search12

## State and idempotency

Gateway credentials are generated once. Existing runtime credentials are preserved. Existing Cloudflare Tunnel state is reused when it matches the configured account and tunnel. Existing DNS records are validated; conflicting records fail instead of being silently replaced.

Sing-box configuration is validated before activation and the previous configuration is backed up before replacement.

## Client bundle

Bootstrap generates the complete bundle under the selected normal user's home directory:

```text
/home/<user>/vpn-client/
```

It includes per-protocol files and aggregated import artifacts for v2rayN and other clients.

The generator reads the live sing-box configuration, so the final client parameters come from the active service rather than a second manually maintained configuration source.
