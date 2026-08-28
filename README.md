# VPS Gateway Infrastructure

Minimal, reproducible, and security-focused Debian personal gateway framework.

This repository turns a manually configured VPS gateway into a reproducible
infrastructure deployment pipeline. It now supports a conservative gateway
profile and an explicit resilient profile with optional multi-transport
sing-box and private DNS/SNI steering.

## Architecture

```text
                 personal clients
                       |
        +--------------+--------------+
        |              |              |
      VLESS       Shadowsocks       SOCKS
        |              |              |
        +--------------+--------------+
                       v
                   sing-box
                       |
                    direct
                       |
                    Internet

 DNS clients -> private sniproxy DNS -> selected HTTPS -> SNI relay -> Internet
                              \-> normal DNS -> normal destination
```

The DNS layer is selective traffic steering, not a universal censorship,
sanctions, or VPN mechanism. It changes the network path for explicitly listed
TLS/HTTP domains. Provider/account policy can still reject the request.

## Profiles

- `default`: conservative VLESS + local authenticated SOCKS; no optional daemons.
- `gateway-minimal`: the documented minimal gateway; VLESS on 443 and local SOCKS.
- `gateway-resilient`: VLESS on 8443, Shadowsocks on 8444, local SOCKS, and
  private DNS/SNI steering on UDP/TCP 53 plus HTTPS 443.

VMess, Trojan, Hysteria2, and TUIC are implemented as independent sing-box
feature flags but remain disabled in the resilient profile until their TLS
certificate/key and operational requirements are supplied.

## DNS steering

`mosajjal/sniproxy` is used instead of a custom SNI proxy. The repository pins
sniproxy `v2.4.1`. The domain inventory is explicit and service-oriented at
`config/gateway/domains/ai-domains.txt`.

DNS access is source-CIDR restricted and ends with reject rules, so the gateway
is not an unrestricted public recursive resolver.

## Security boundaries

- disabled transports do not open firewall ports
- SOCKS is loopback-only by default
- DNS is disabled unless the resilient profile is selected
- cloudflared is optional
- secrets are external runtime inputs
- generated client artifacts are mode `0600`
- SSH hardening remains part of deployment

## Deployment

Minimal:

```sh
sudo ./deploy/deploy.sh --profile gateway-minimal --env-file /root/vps-gateway-runtime.conf
```

Resilient:

```sh
sudo ./deploy/deploy.sh --profile gateway-resilient --env-file /root/vps-gateway-runtime.conf
```

Dry-run:

```sh
./deploy/deploy.sh --dry-run --profile gateway-resilient --env-file /path/to/test.env
```

## Testing

Repository validation:

```sh
./scripts/validate-repository.sh
```

Local rendering and policy tests:

```sh
./tests/test-local.sh
./tests/test-resilient.sh
```

Connectivity audit:

```sh
./scripts/gateway-connectivity-audit.sh config/gateway/domains/ai-domains.txt
```

The audit distinguishes DNS, TCP, TLS, and HTTP/application outcomes instead of
calling every HTTP error a network failure.

## Design principles

The project remains source-driven and Debian-native. It does not replace the
existing deployment pipeline with Docker Compose or a large orchestration layer.
Optional components are independently configurable and the minimal deployment
remains deliberately small.
