# Architecture

This repository provisions two independent network capabilities on a Debian/Ubuntu VPS:

1. **sing-box gateway** — authenticated proxy endpoints rendered from the gateway profile.
2. **Tailscale exit node** — optional network-layer egress for tailnet clients that explicitly select this VPS.

Neither capability depends on the other. The sing-box outbound is currently direct; configuring Tailscale does not silently reroute sing-box traffic through the tailnet.

## Runtime topology

```text
Gateway clients -> enabled sing-box inbounds -> direct outbound -> Internet

Tailscale clients -> tailnet -> VPS exit node -> Internet

Optional / not in default install path:
DNS client -> DNS steering + SNI relay -> selected HTTPS destination
```

## Inbound exposure policy

The gateway deliberately uses a hybrid network model rather than forcing every protocol through Cloudflare:

- **Cloudflare Tunnel over HTTPS/443:** VLESS WebSocket at `/vless-ws`, VMess WebSocket at `/vmess-ws`, and VLESS HTTPUpgrade at `/vless-hu`. Their sing-box origins bind to loopback ports 18080, 18081, and 18082; those origin ports are not public firewall ingress.
- **Direct public TCP/UDP:** VLESS Reality TCP/8443; Shadowsocks TCP/8444; Shadowsocks 2022 TCP/8445; Hysteria2 UDP/8446; TUIC UDP/8447; Trojan TCP/8448; AnyTLS TCP/8449; and VLESS gRPC TCP/8450. The enabled direct protocols are intentional parts of the gateway profile, not Cloudflare Tunnel routes.
- **Public authenticated proxies:** SOCKS5 TCP/1080 and HTTP proxy TCP/8080 are intentionally exposed on public interfaces by the gateway profile. They use the configured SOCKS/HTTP username and password. Keep those credentials strong and private.
- **Management:** SSH is TCP/22 and uses administrator public-key authentication; root SSH login and password-based SSH authentication are disabled after the verified migration.

UFW recreates this profile's public ingress allow-list, including the intended IPv4/IPv6 rules. The direct hostname is DNS-only and does not proxy raw TCP/UDP transports. A Cloudflare DNS record by itself does not tunnel a direct inbound.

## Component boundaries

- `sing-box`: authenticated proxy inbounds and the configured outbound (currently direct).
- `cloudflared`: optional tunnel client for the WebSocket/HTTP-based transports.
- `tailscaled`: optional Tailscale overlay and advertised exit-node capability.
- UFW: the gateway firewall is authoritative and may reset/rebuild ingress rules. Once Tailscale is explicitly configured, its WAN interface is recorded under `/etc/vps-gateway/tailscale-exit-node.conf`; managed UFW resets read that state and recreate the `tailscale0` forwarding rule. Initial gateway bootstrap does not install or enable Tailscale.
- `sniproxy`: optional DNS and TLS SNI steering components. These are not enabled by the default profile and are not a supported default deployment path yet.

## Tailscale exit-node behavior

Run the opt-in script only after the gateway bootstrap and initial self-audit have completed, so its forwarding rule is applied after the initial UFW reset. The script requires UFW to be active, enables IPv4/IPv6 forwarding, installs/authenticates Tailscale, advertises the VPS as an exit node, records the detected WAN interface, and configures UFW forwarding. The exit-node feature must then be approved in the Tailscale admin console. Each client separately selects the node. Tailnet ACL/grant policy must permit internet routing where custom policies are used. A later managed UFW reset reconstructs the forwarding rule from the saved interface.

Tailscale exit-node routing is network-layer routing for selected tailnet clients. It is not a sing-box outbound and does not alter the generated sing-box configuration.

## DNS steering status

DNS steering is **not a default capability** in the current install path. Files for the DNS/SNI approach remain in the repository, but the end-to-end setup, firewall exposure, runtime validation, and test coverage are not currently aligned well enough to promise it as operational. Do not point client DNS settings at the VPS expecting the feature to work. If reactivated later, it needs its own explicitly enabled install path and end-to-end tests.

Even a working SNI steering path would not guarantee service access: destination filtering, account or regional policy, application authentication, HTTP errors, and non-TLS protocols may still prevent a request from succeeding.

## Multi-transport model

Each sing-box inbound is controlled by feature flags such as:

```text
ENABLE_VLESS
ENABLE_SHADOWSOCKS
ENABLE_VMESS
ENABLE_TROJAN
ENABLE_HYSTERIA2
ENABLE_TUIC
ENABLE_SOCKS
```

TLS transports require valid certificate/key material when enabled. The renderer validates generated JSON and the CI test checks the current gateway profile with the pinned sing-box binary.

## Secret model

Secrets are read from an ignored runtime environment file. Generated sing-box configuration is mode 0600. Client generation intentionally omits Reality private keys and Cloudflare tunnel tokens.

## Failure model

Connectivity tests should distinguish:

- DNS resolution failure
- TCP/UDP reachability failure
- TLS handshake failure
- HTTP/application response

An HTTP 401, 403, 404, or 429 after successful DNS/TCP/TLS is evidence that the network path reached the service, not proof that the application request succeeded.
