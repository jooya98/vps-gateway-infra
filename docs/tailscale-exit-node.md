# Optional Tailscale exit node

Tailscale exit-node mode is an independent, opt-in capability. It does not change sing-box configuration or route sing-box outbound traffic through Tailscale.

## Required order

1. Run `sudo bash ./bootstrap.sh` and wait for the initial read-only self-audit to pass.
2. From the same repository checkout, run:

   ```bash
   sudo bash ./scripts/configure-tailscale-exit-node.sh
   ```

The Tailscale setup is intentionally not part of the initial bootstrap. The script requires UFW to be active, installs Tailscale from the official installer if absent, enables IPv4/IPv6 forwarding, starts `tailscaled`, and advertises this VPS as an exit node. If authentication is required, complete the URL printed by Tailscale and rerun the script; it records the configuration only after the Tailscale backend reports `Running`.

## Firewall persistence

The script detects the default IPv4 route interface and stores it in the root-owned file:

```text
/etc/vps-gateway/tailscale-exit-node.conf
```

The file contains the non-secret `WAN_IF` interface name and is mode `0600`. The script adds a UFW forwarding rule from `tailscale0` to that interface.

The gateway firewall is authoritative and can reset UFW when it applies its allow-list. To prevent that reset from breaking the exit node, `scripts/apply-firewall.sh` checks for the recorded Tailscale state and recreates the forwarding rule after the reset. If there is no state file, Tailscale forwarding is not added. Do not delete the state file while relying on this exit node.

## Tailnet and clients

After the script succeeds:

1. In the Tailscale admin console, approve this machine for use as an exit node (unless tailnet policy auto-approves it).
2. Select this machine as the exit node on each client that should route internet traffic through it.
3. Ensure custom tailnet ACL/grant policy permits exit-node traffic to `autogroup:internet`.
4. Verify real client traffic and the public egress IP; a successful local script does not prove provider forwarding or tailnet policy.

Exit-node advertisement alone does not cause clients to use this node.

## Validation

Read-only dry-run of the installation plan:

```bash
DRY_RUN=1 bash ./scripts/configure-tailscale-exit-node.sh
DRY_RUN=1 RESET_UFW=1 bash ./scripts/apply-firewall.sh
```

When Tailscale is configured, the saved state can also be tested without changing the host by pointing the dry-run to a state file containing a valid line such as `WAN_IF=ens3`:

```bash
DRY_RUN=1 RESET_UFW=1 TAILSCALE_EXIT_NODE_STATE_FILE=/path/to/test-state bash ./scripts/apply-firewall.sh
```

Run `sudo bash ./scripts/self-audit.sh` after enabling Tailscale and after any later firewall changes. With the state file present, the audit checks IPv4/IPv6 forwarding, the UFW route rule, and the Tailscale backend.

## Relationship to sing-box

- Tailscale exit node: network-layer routing for clients explicitly selecting this node.
- sing-box gateway: authenticated proxy endpoints configured by the gateway profile.
- Neither feature is a prerequisite for the other. Tailscale configuration does not rewrite sing-box config; deploying sing-box does not advertise a Tailscale exit node.
