# Deployment

## Minimal profile

```sh
sudo ./deploy/deploy.sh --profile gateway-minimal --env-file /root/vps-gateway-runtime.conf
```

The minimal profile keeps VLESS on 443 and authenticated SOCKS on loopback. It
does not install sniproxy or cloudflared and does not expose additional
transport ports.

## Resilient profile

Create a runtime environment containing the existing VLESS/Reality secrets,
plus `TRANSPORT_PASSWORD`, `SNIPROXY_PUBLIC_IPV4`, and (when TLS transports are
enabled) `TLS_SERVER_NAME`, `TLS_CERT_PATH`, and `TLS_KEY_PATH`.

Then:

```sh
sudo ./deploy/deploy.sh --profile gateway-resilient --env-file /root/vps-gateway-runtime.conf
```

The resilient profile installs sing-box and sniproxy. It binds sniproxy DNS to
UDP/TCP 53 and HTTPS SNI relay to 443, so VLESS moves to 8443. The firewall is
derived from the profile rather than from a permanently open port list.

## DNS client access

Set `DNS_ALLOWED_CIDRS` to the exact client networks that should be allowed to
query the gateway. The default only permits localhost. Do not replace the
source ACL with `0.0.0.0/0` unless you deliberately want a public DNS service.

The domain inventory is `config/gateway/domains/ai-domains.txt`. Add a domain
only when there is a concrete reason to steer that service through the VPS.

## Cloudflared

Cloudflared is disabled by default. To use it, set `ENABLE_CLOUDFLARED=true` and
provide `CLOUDFLARED_TUNNEL_TOKEN`. Its installation, unit, and firewall behavior
are then included; otherwise the gateway does not depend on a tunnel token.

## Client artifacts

After deployment, the client generator can create artifacts for every enabled
transport:

```sh
sudo ./scripts/generate-client-profiles.sh
```

Artifacts are written with mode `0600`. The generator does not emit Reality
private keys or Cloudflare tunnel tokens.

## Connectivity audit

Use the audit utility against the curated inventory:

```sh
./scripts/gateway-connectivity-audit.sh config/gateway/domains/ai-domains.txt
```

For a SOCKS path:

```sh
PROXY='socks5h://user:password@127.0.0.1:1080' \
  ./scripts/gateway-connectivity-audit.sh config/gateway/domains/ai-domains.txt
```

The audit intentionally separates network-layer failures from application
responses. A `403`, `401`, `404`, or `429` after successful DNS/TCP/TLS proves
that the network path reached the service even though the application rejected
or limited the request.

## Rollback

The existing managed-state backup and rollback workflow remains in place. A
real deployment creates the backup before installing new binaries or managed
configuration.
