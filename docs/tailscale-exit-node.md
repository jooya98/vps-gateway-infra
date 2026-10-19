# Optional Tailscale exit node

Tailscale exit-node mode is an independent, opt-in capability. It does not change sing-box configuration or route sing-box outbound traffic through Tailscale.

Run as root on a fresh Debian/Ubuntu VPS:

```bash
sudo bash ./scripts/configure-tailscale-exit-node.sh
```

The script installs Tailscale from its official installer if absent, enables IPv4/IPv6 forwarding, adds a UFW forwarding rule from tailscale0 to the detected default-route interface, enables tailscaled, and advertises the node as an exit node. If the node is not authenticated, tailscale up prints an authentication URL. Complete that login, then approve the exit-node capability in the Tailscale admin console.

On clients, select this machine as the exit node in the Tailscale client. The client must be signed into the same tailnet and permitted by tailnet policy. Exit-node advertisement alone does not make it automatically selected.

Dry-run:

```bash
DRY_RUN=1 bash ./scripts/configure-tailscale-exit-node.sh
```

The script does not reset UFW rules. Tailscale uses its own NAT/firewall integration by default; if host firewall policy or provider networking differs, verify forwarded traffic and return traffic from an actual client before relying on this node.

## Relationship to sing-box

- Tailscale exit node: network-layer routing for clients explicitly selecting this node.
- sing-box gateway: authenticated proxy endpoints configured by the gateway profile.
- Neither feature is a prerequisite for the other. Tailscale configuration does not rewrite sing-box config; deploying sing-box does not advertise a Tailscale exit node.
