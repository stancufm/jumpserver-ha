# Standby jumpserver runbook

This node passively pulls approved state from the active peer. It never starts
GR collection or installs package proposals as a consequence of synchronization.

## Normal validation

```text
systemctl status shadow-ha-sync.timer shadow-ha-apply.path
cat /var/lib/shadow-ha-sync/last-success
sudo shadow-ha-packages plan
sudo journalctl -u shadow-ha-sync -u shadow-ha-apply --no-pager -n 100
```

The MOTD shows the HA role and last successful apply. A missing or stale value
is an operational alert. Validate that the active physical address, pinned host
key and VIP in `/etc/jumpserver-ha/role.conf` are still correct.

## Package proposal

Review missing, different and extra packages. Synchronization never changes the
installed set. If missing packages are approved:

```text
sudo shadow-ha-packages apply --yes --update
```

Review services started by package maintainer scripts afterwards. Version
differences are not forced automatically.

## Incident and promotion

1. Confirm the active peer is unavailable.
2. Exclude split-brain and determine VIP ownership.
3. Review `last-success`, the archive hash and both synchronization journals.
4. Validate users, home ownership and the GR archive on standby.
   In full-clone mode, validate local login and password aging with a designated
   test account; never print `/etc/shadow` or private credential files.
5. Review the package proposal; install only approved missing prerequisites.

The selected user's UID and primary GID must match the active node. Different
numeric GIDs for existing supplementary package groups are expected and are
resolved by group name; do not renumber local system groups to make them match.
6. Move/promote the VIP according to the network runbook.
7. Enable only approved GR timers after the standby is authoritative.

Do not enable operational timers merely because synchronization or package
installation completed.

## Secrets and vault recovery

When full clone is approved, selected local password hashes, the encrypted
store and private material are present on standby. The same local password can
therefore authenticate when PAM uses `/etc/shadow`; external RADIUS/LDAP still
depends on its own replicated configuration, packages and upstream service.
GPG can still require an interactive unlock after reboot. Do not remove
passphrase protection solely to make failover unattended.
