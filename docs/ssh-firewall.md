# Standard SSH and firewall policy

The node policy is uniform: SSH on TCP/22; a non-root administrator with a public key; root SSH login, password authentication, and keyboard-interactive authentication disabled; UFW default deny incoming and allow outgoing; only enabled gateway ports opened.

The firewall script is additive. It does not reset UFW or delete unrelated host rules.

## Safe deployment sequence

1. Provision the non-root administrator and install the intended public key.
2. Add the SSH and enabled gateway allow-rules, then enable UFW.
3. Open a second terminal from the operator workstation and log in as the administrator using the intended private key.
4. In that second session, verify `sudo -v` and `sudo id -u`; the latter must print `0`.
5. Only then confirm the prompt in the original deployment session. The hardening script requires explicit confirmation and independently checks the key file owner, mode, and effective sshd policy.
6. Validate the effective SSH policy and reload the service. The main SSH config and provider drop-ins are backed up before changes; provider drop-ins are moved out of the active path, and the previous configuration is restored if syntax/effective-policy validation or reload fails.

Keep the original root/VNC console session open until the new admin session has been verified after hardening. VNC is a recovery path, not a substitute for testing the intended SSH key.

## Manual recovery

Use the provider VNC/serial console to inspect `/var/lib/vps-gateway/ssh-backups/`. Restore the relevant `sshd_config` and `sshd_config.d` backup, then run `sshd -t` and reload `ssh` (or `sshd`). Provider drop-ins are preserved under the backup's `disabled-provider-dropins/` directory as well as in the full `sshd_config.d` snapshot. Do not delete backups until the new policy has been verified.
