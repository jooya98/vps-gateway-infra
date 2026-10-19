# Standard SSH and firewall policy

The node policy is uniform: SSH on TCP/22; a non-root administrator with a public key; root SSH login, password authentication, and keyboard-interactive authentication disabled; UFW default deny incoming and allow outgoing; only enabled gateway ports opened.

The firewall policy is intentionally authoritative. During migration it adds the new allow-list without removing provider rules; after SSH key login is verified and SSH hardening succeeds, it resets UFW and recreates only the declared policy rules.

## Safe deployment sequence

1. Provision the non-root administrator and install the intended public key.
2. Back up the provider SSH configuration and drop-ins, then switch the SSH listener to TCP/22 with root/password login temporarily retained.
3. Add TCP/22 and enabled gateway allow-rules without deleting the existing provider firewall rules.
4. Open a second terminal from the operator workstation and log in as the administrator using the intended private key on port 22.
5. In that second session, verify `sudo -v` and `sudo id -u`; the latter must print `0`.
6. Only then confirm the prompt in the original deployment session. The hardening script applies the strict SSH policy and validates the effective configuration before reload.
7. Once SSH hardening succeeds, reset UFW and recreate only the repository-defined allow-list. This deliberately removes provider-specific firewall rules.

Keep the original root/VNC console session open until the new admin session has been verified after hardening. VNC is a recovery path, not a substitute for testing the intended SSH key.

## Manual recovery

Use the provider VNC/serial console to inspect `/var/lib/vps-gateway/ssh-backups/`. Restore the relevant `sshd_config` and `sshd_config.d` backup, then run `sshd -t` and reload `ssh` (or `sshd`). Provider drop-ins are preserved under the backup's `disabled-provider-dropins/` directory as well as in the full `sshd_config.d` snapshot. Do not delete backups until the new policy has been verified.
