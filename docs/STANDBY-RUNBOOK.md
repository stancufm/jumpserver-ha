# Standby jumpserver runbook

This node is the passive/DR peer. It pulls a fixed export from the active node
every five minutes. It never starts GR collection or other operational timers
as a consequence of synchronization or software installation.

## Normal validation

```bash
systemctl status shadow-ha-sync.timer jumpserver-ha-update.timer
cat /var/lib/shadow-ha-sync/last-success
sudo journalctl -u shadow-ha-sync --no-pager -n 100
sudo jumpserver-ha-update --check
```

`jumpserver-ha-update.timer` is a daily **check only**. It downloads the public
HTTPS source archive with `wget`, compares the local and remote `VERSION`,
records that result in `/var/lib/jumpserver-ha/last-update-check`, and logs if
an update is available. It never changes the installed checkout.

After reviewing the release, apply it explicitly:

```bash
sudo jumpserver-ha-update --apply
```

The updater stages the archive under `/opt`, retains the prior tree as
`/opt/jumpserver-ha.previous`, and re-runs the idempotent installer. If that
installer fails, it restores the previous tree. It preserves the existing
restricted SSH key and host-key pin; it does not create, copy, or print secrets.
Only commits that increment the repository `VERSION` are eligible for
installation.

## Incident/promotion

1. Confirm that the active peer is unavailable and determine VRRP/VIP ownership.
2. Review `last-success` and the synchronization journal.
3. Use GR and its replicated operational data for diagnosis.
4. Do not enable operational timers until split-brain has been excluded.
5. If the promotion becomes permanent, enable only approved timers explicitly.

## Vault/GPG recovery

The encrypted GR vault and private GPG material are replicated. After a fresh
boot/login, GPG may require one interactive unlock:

```bash
sudo -u mihai.stancu /usr/local/bin/gr vault test mihai.stancu
```

A fully unattended unlock needs a separate approved security design.
