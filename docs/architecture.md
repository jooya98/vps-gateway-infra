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

## Component boundaries

- `sing-box`: authenticated proxy inbounds and the configured outbound (currently direct).
- `cloudflared`: optional tunnel client for the WebSocket/HTTP-based transports.
- `tailscaled`: optional Tailscale overlay and advertised exit-node capability.
- UFW: additive host ingress policy for enabled gateway ports; exit-node configuration adds a forwarding rule without resetting existing UFW rules.
- `sniproxy`: optional DNS and TLS SNI steering components. These are not enabled by the default profile and are not a supported default deployment path yet.

## Tailscale exit-node behavior

The opt-in script enables IPv4/IPv6 forwarding, advertises the VPS as an exit node, and configures the host forwarding rule. The exit-node feature must then be approved in the Tailscale admin console. Each client separately selects the node. Tailnet ACL/grant policy must permit internet routing where custom policies are used.

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
