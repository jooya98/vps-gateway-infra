# Architecture

The repository is a Debian-native personal gateway. The deployment pipeline remains
template-driven; optional components are enabled by profile flags rather than
being installed unconditionally.

## Runtime topology

```text
                         PERSONAL CLIENTS
                               |
          +--------------------+--------------------+
          |                    |                    |
        VLESS             Shadowsocks          other enabled
          |                    |                 transports
          +--------------------+--------------------+
                               |
                            sing-box
                               |
                             direct
                               |
                           Internet

 DNS client -> sniproxy DNS policy -> selected domain -> VPS:443 -> SNI relay -> destination
                           \-> normal domain -> upstream DNS -> destination
```

## Component boundaries

- `sing-box`: authenticated proxy inbounds and direct outbound traffic.
- `sniproxy`: optional DNS + TLS SNI steering. It does not terminate TLS for
  the normal steering path.
- `cloudflared`: optional tunnel client, independent of the gateway profile.
- UFW: derives ingress rules from enabled protocol flags.

## DNS steering semantics

The DNS layer is not a public recursive resolver. Its source CIDR ACL contains
explicit allowed networks followed by reject-all rules. The domain ACL contains
only selected service FQDNs.

For a selected domain:

1. client asks the gateway DNS server for the domain;
2. the domain ACL causes sniproxy to return the VPS public address;
3. the client opens the normal HTTPS connection to port 443;
4. sniproxy reads the TLS SNI and opens a connection to the real destination;
5. encrypted application traffic passes through without TLS termination.

For all other domains, DNS resolution is forwarded upstream and the client gets
the normal destination address.

This does not guarantee service access. Destination filtering, account policy,
regional policy, application authentication, HTTP errors, or non-TLS protocols
can still prevent a request from succeeding.

## 443 trade-off

A DNS-only steering mechanism cannot change an HTTPS destination port. Therefore
`gateway-resilient` assigns 443 to sniproxy and moves VLESS to 8443. This is an
intentional architectural trade-off. The minimal profile keeps VLESS on 443.

## Multi-transport model

Each sing-box inbound has an independent feature flag:

```text
ENABLE_VLESS
ENABLE_SHADOWSOCKS
ENABLE_VMESS
ENABLE_TROJAN
ENABLE_HYSTERIA2
ENABLE_TUIC
ENABLE_SOCKS
```

VMess/Trojan/Hysteria2/TUIC require external certificate/key material when
TLS is enabled. They are supported by the renderer but disabled by default.

## Secret model

Secrets are read from an ignored runtime environment file. Generated config is
mode `0600`. Client generation intentionally omits Reality private keys and
Cloudflare tunnel tokens.

## Failure model

Connectivity tests classify failures by layer:

```text
DNS failure
TCP failure
TLS failure
HTTP/application response
```

An HTTP `401`, `403`, `404`, or `429` after successful DNS/TCP/TLS is evidence
of a functioning network path, not a DNS/TCP/TLS failure.
